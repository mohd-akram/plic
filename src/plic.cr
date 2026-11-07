require "base64"
require "http/server"
require "openssl"
require "option_parser"

require "sqlite3"

def indent(string, space)
  string.each_line do |line|
    yield space unless line.empty?
    yield line
    yield '\n'
  end
end

{% for tag in %w(script style) %}
def {{tag.id}}(string)
  String.build do |str|
    str << '\n'
    indent string, " " * 6 { |s| str << s }
    str << " " * 4
  end
end
{% end %}

def hash(string)
  hash = OpenSSL::Digest.new "SHA256"
  hash.update string
  Base64.strict_encode hash.final
end

def not_found(context)
  context.response.status_code = 404
  context.response.print "Not Found"
end

def not_allowed(context, allow)
  context.response.status_code = 405
  context.response.headers["Allow"] = allow
  context.response.print "Method Not Allowed"
end

css = style <<-'CSS'
main {
  text-align: center;
}
textarea {
  max-width: 96%;
}
details {
  max-width: 30rem;
  margin-left: auto;
  margin-right: auto;
}
details ol {
  text-align: left;
}
CSS
css_hash = hash css

js = script <<-'JS'
'use strict';

/* Helpers */
function b64encode(b) {
  return b.toBase64({ alphabet: 'base64url', omitPadding: true });
}

function b64decode(s) {
  return Uint8Array.fromBase64(s, { alphabet: 'base64url' });
}

/* Crypto */
const KEY_ALGORITHM = { name: 'AES-GCM', length: 128 };
const IV_LENGTH = 12;

const KDF_ALGORITHM = { name: 'PBKDF2', hash: 'SHA-256', iterations: 6e5 };
const SALT_LENGTH = 16;

const HASH_ALGORITHM = 'SHA-256';

const ID_LENGTH = 16;

async function deriveKey(password, salt, usage) {
  const rawPassword = new TextEncoder().encode(password);

  const key = await window.crypto.subtle.importKey(
    'raw', rawPassword, KDF_ALGORITHM, false, ['deriveKey']
  );

  return await window.crypto.subtle.deriveKey(
    Object.assign({ salt }, KDF_ALGORITHM),
    key, KEY_ALGORITHM, false, [usage]
  );
}

async function importKey(rawKey) {
  return await crypto.subtle.importKey(
    'raw', rawKey, KEY_ALGORITHM, false, ['decrypt']
  );
}

async function createEnvelope(message, password = null) {
  const rawMessage = new TextEncoder().encode(message);

  let key, salt;
  if (password) {
    salt = window.crypto.getRandomValues(new Uint8Array(SALT_LENGTH));
    key = await deriveKey(password, salt, 'encrypt');
  } else {
    key = await window.crypto.subtle.generateKey(
      KEY_ALGORITHM, true, ['encrypt']
    );
  }

  const iv = window.crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const ciphertext = new Uint8Array(await window.crypto.subtle.encrypt(
    Object.assign({ iv }, KEY_ALGORITHM), key, rawMessage
  ));

  const data = password ?
    new Blob([salt, iv, ciphertext]) :
    new Blob([iv, ciphertext]);

  const digest = new Uint8Array(
    await crypto.subtle.digest(HASH_ALGORITHM, await data.arrayBuffer())
  );
  const id = b64encode(digest.subarray(0, ID_LENGTH));
  let url = `${window.location.origin}/${id}`;
  if (!password) {
    const rawKey = new Uint8Array(
      await window.crypto.subtle.exportKey('raw', key)
    );
    url += `#${b64encode(rawKey)}`;
  }

  return { data, url };
}

async function decryptRawEnvelope(rawEnvelope, key) {
  const iv = rawEnvelope.subarray(0, IV_LENGTH);
  const ciphertext = rawEnvelope.subarray(IV_LENGTH);
  const rawMessage = await window.crypto.subtle.decrypt(
    Object.assign({ iv }, KEY_ALGORITHM), key, ciphertext
  );
  const message = new TextDecoder().decode(rawMessage);
  return message;
}

/* Event Listeners */
async function onGetLink(form) {
  const messageElement = form.elements.namedItem('message');
  const passwordElement = form.elements.namedItem('password');

  const message = messageElement.value;
  const password = passwordElement.value;

  const envelope = await createEnvelope(message, password);

  const body = new FormData;
  body.append('data', envelope.data);

  const response = await fetch('/', { method: 'POST', body });

  if (response.ok) {
    messageElement.value = envelope.url;
    messageElement.readOnly = true;
    messageElement.select();
    const labelElement = form.querySelector('label[for=message]');
    try {
      await navigator.clipboard.writeText(envelope.url);
      labelElement.textContent = 'Link (copied to clipboard)';
    } catch {
      labelElement.textContent = 'Link';
    }
    passwordElement.disabled = true;
  } else {
    throw 'Could not save message';
  }
}

async function onGetMessage(form) {
  const messageElement = form.elements.namedItem('message');
  const passwordElement = form.elements.namedItem('password');

  const encodedEnvelope = messageElement.dataset.envelope;
  const password = passwordElement.value;

  let rawEnvelope;
  if (encodedEnvelope) {
    rawEnvelope = b64decode(encodedEnvelope);
  } else {
    const response = await fetch('', { method: 'DELETE' });
    if (response.ok) {
      rawEnvelope = new Uint8Array(await response.arrayBuffer());
      const digest = new Uint8Array(
        await crypto.subtle.digest(HASH_ALGORITHM, rawEnvelope)
      );
      const id = b64encode(digest.subarray(0, ID_LENGTH));
      if (id == location.pathname.slice(1)) {
        messageElement.dataset.envelope = b64encode(rawEnvelope);
        window.onbeforeunload = event => event.preventDefault();
      } else {
        rawEnvelope = null;
      }
    }
  }

  if (rawEnvelope) {
    let key;
    if (password) {
      const salt = rawEnvelope.subarray(0, SALT_LENGTH);
      rawEnvelope = rawEnvelope.subarray(SALT_LENGTH);
      key = await deriveKey(password, salt, 'decrypt');
    } else {
      try {
        key = await importKey(b64decode(location.hash.slice(1)));
      } catch {
        throw 'Invalid secret key';
      }
    }
    let message;
    try {
      message = await decryptRawEnvelope(rawEnvelope, key);
    } catch {
      throw password ? 'Wrong password' : 'Wrong secret key';
    }
    messageElement.value = message;
    form.querySelector('label[for=message]').textContent = 'Message';
    passwordElement.disabled = true;
    window.onbeforeunload = null;
  } else {
    throw 'Message not found';
  }
}

function addSubmitListener(form, handler) {
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const submitButton = form.querySelector('[type=submit]');
    submitButton.disabled = true;
    try {
      await handler(form);
    } catch (err) {
      submitButton.disabled = false;
      if (typeof err == 'string') alert(err);
      else throw err;
    }
  });
}

async function main() {
  const form = document.forms.namedItem('letter');

  if (location.pathname == '/') {
    addSubmitListener(form, onGetLink);
  } else {
    const messageElement = form.elements.namedItem('message');
    messageElement.readOnly = true;
    messageElement.value = location.href;
    form.querySelector('label[for=message]').textContent = 'Link';
    if (!location.hash.slice(1)) {
      form.querySelector('label[for=password]').textContent = 'Password';
      form.elements.namedItem('password').required = true;
    } else {
      form.querySelector('label[for=password]').hidden = true;
      form.elements.namedItem('password').hidden = true;
    }
    form.querySelector('input[type=submit]').value = 'Get and Delete Message';
    addSubmitListener(form, onGetMessage);
  }
}

document.addEventListener('DOMContentLoaded', main);
JS
js_hash = hash js

html = <<-HTML
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="color-scheme" content="light dark">
    <meta name="viewport" content="initial-scale=1">
    <title>plic</title>
    <meta name="description"
      content="Send one-time secret messages securely with plic.">
    <style>#{css}</style>
    <script>#{js}</script>
  </head>
  <body>
    <main>
      <h1 title="envelope in Romanian">plic</h1>
      <form name="letter" method="POST">
        <p>
          <label for="message">Message</label><br>
          <textarea id="message" rows="10" cols="50"
            maxlength="980" required></textarea>
        </p>
        <p>
          <label for="password">Password (optional)</label>
          <input id="password" type="password" minlength="12">
        </p>
        <input type="submit" value="Get Link">
      </form>
      <p>Use plic to send a one-time secret message.</p>
      <details>
        <summary>How it works</summary>
        <ol>
          <li>A secret key is generated and used to encrypt the message.</li>
          <li>The encrypted message is sent to the server which hashes it to
            generate an ID.</li>
          <li>The same hashing is performed in the browser and the ID is used to
            form the shareable link.</li>
          <li>The secret key is appended to the private part of the link that
            is never sent to the server.</li>
          <li>When a link is opened, the encrypted message is simultaneously
            retrieved and deleted from the server.</li>
          <li>The encrypted message is hashed to ensure it matches the ID.</li>
          <li>The secret key in the link is used to decrypt the data and the
            message is displayed.</li>
        </ol>
        <p>
          Technical details along with source code are available at
          github.com/mohd-akram/plic.
        </p>
      </details>
    </main>
  </body>
</html>
HTML

port = 8080
db_path = "data.db"

OptionParser.parse do |parser|
  parser.banner = "usage: plic [options]"
  parser.on("--port port", "Server port") { |p| port = p.to_i }
  parser.on("--db path", "SQLite database file path") do |path|
    db_path = path
  end
  parser.on("-h", "--help", "Show this help") { puts parser; exit }
  parser.invalid_option do |option|
    STDERR.puts "plic: unrecognized option '#{option}'"
    STDERR.puts parser
    exit(1)
  end
end

db_url = "sqlite3://#{db_path}"

csp = "base-uri 'none'; " \
      "block-all-mixed-content; " \
      "connect-src 'self'; " \
      "default-src 'none'; " \
      "form-action 'none'; " \
      "frame-ancestors 'none'; " \
      "script-src 'sha256-#{js_hash}'; " \
      "style-src 'sha256-#{css_hash}'"

server = HTTP::Server.new do |context|
  path = context.request.path

  unless /^\/[A-Za-z0-9_-]*$/.matches?(path)
    not_found context
    next
  end

  case context.request.method
  when "GET"
    unless path == "/"
      context.response.headers["X-Robots-Tag"] = "none"
    end
    context.response.headers["Content-Security-Policy"] = csp
    context.response.headers["Referrer-Policy"] = "no-referrer"
    context.response.content_type = "text/html; charset=utf-8"
    context.response.print html
  when "POST"
    case path
    when "/"
      id = nil
      data = nil
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "data"
          body = Bytes.new 1024
          size = part.body.read_greedy body
          if part.body.read_byte.nil?
            data = body[0, size]
            digest = OpenSSL::Digest.new("SHA256")
            digest.update data
            id = Base64.urlsafe_encode digest.final[0, 16], padding: false
          else
            context.response.status_code = 413
            context.response.print "Content Too Large"
            next
          end
        end
      end
      if data
        DB.open db_url do |db|
          db.exec "insert into envelopes (id, data) values (?, ?)", id, data
        end
      else
        context.response.status_code = 400
        context.response.print "Bad Request"
      end
    else
      not_allowed context, "GET, DELETE"
    end
  when "DELETE"
    case path
    when "/"
      not_allowed context, "GET, POST"
    else
      id = path.split('/')[1]
      data = nil
      DB.open db_url do |db|
        begin
          data = db.query_one \
            "delete from envelopes where id = ? returning data", id,
              &.read(Bytes)
        rescue ex : DB::Error
        end
      end
      if data
        context.response.content_type = "application/octet-stream"
        context.response.write data
      else
        not_found context
      end
    end
  end
end

DB.open db_url do |db|
  db.exec (
    "create table if not exists envelopes (" \
    "  id text primary key," \
    "  data blob not null," \
    "  created timestamp default current_timestamp" \
    ") without rowid"
  )
end

server.bind_tcp port
puts "Listening on http://127.0.0.1:#{port}"
server.listen

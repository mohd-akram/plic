require "http/server"
require "option_parser"

require "sqlite3"

def indent(string, space)
  string.each_line do |line|
    yield space
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
  Base64.strict_encode hash.digest
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
textarea, details {
  max-width: 96%;
}
details {
  display: inline;
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
  return btoa(String.fromCharCode(...new Uint8Array(b)))
    .replace(/={1,2}$/, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function b64decode(s) {
  return Uint8Array.from(
    atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)
  ).buffer;
}

/* Crypto */
const KEY_ALGORITHM = { name: 'AES-GCM', length: 128 };
const IV_LENGTH = 12;
const TAG_LENGTH = 16;

const KDF_ALGORITHM = { name: 'PBKDF2', hash: 'SHA-256', iterations: 100000 };
const SALT_LENGTH = 16;

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
  const ciphertext = await window.crypto.subtle.encrypt(
    Object.assign({ iv }, KEY_ALGORITHM), key, rawMessage
  );

  const data = password ?
    new Blob([salt, iv, ciphertext]) :
    new Blob([iv, ciphertext]);

  const id = b64encode(ciphertext.slice(-TAG_LENGTH));
  let url = `${window.location.origin}/${id}`;
  if (!password) {
    const rawKey = await window.crypto.subtle.exportKey('raw', key);
    url += `#${b64encode(rawKey)}`;
  }

  return { data, url };
}

async function decryptRawEnvelope(rawEnvelope, key) {
  const iv = rawEnvelope.slice(0, IV_LENGTH);
  const ciphertext = rawEnvelope.slice(IV_LENGTH);
  const rawMessage = await window.crypto.subtle.decrypt(
    Object.assign({ iv }, KEY_ALGORITHM), key, ciphertext
  );
  const message = new TextDecoder().decode(rawMessage);
  return message;
}

/* Event Listeners */
async function onGetLink(event) {
  event.preventDefault();

  const form = event.currentTarget;
  const messageElement = form.elements.namedItem('message');

  const message = messageElement.value;
  const password = form.elements.namedItem('password').value;

  const envelope = await createEnvelope(message, password);

  const body = new FormData;
  body.append('data', envelope.data);

  const response = await fetch('/', { method: 'POST', body });

  if (response.ok) {
    messageElement.value = envelope.url;
    messageElement.select();
    form.querySelector('label[for=message]').innerText = 'Link';
    disableInteraction(form);
  } else {
    alert('Error: Could not save message');
  }
}

async function onGetMessage(event) {
  event.preventDefault();

  const form = event.currentTarget;
  const messageElement = form.elements.namedItem('message');
  const password = form.elements.namedItem('password').value;

  const encodedEnvelope = messageElement.dataset.envelope;

  let rawEnvelope;
  if (encodedEnvelope) {
    rawEnvelope = b64decode(encodedEnvelope);
  } else {
    const response = await fetch('', { method: 'DELETE' });
    if (response.ok) {
      rawEnvelope = await response.arrayBuffer();
      messageElement.dataset.envelope = b64encode(rawEnvelope);
    }
  }

  if (rawEnvelope) {
    let key;
    if (password) {
      const salt = rawEnvelope.slice(0, SALT_LENGTH);
      rawEnvelope = rawEnvelope.slice(SALT_LENGTH);
      key = await deriveKey(password, salt, 'decrypt');
    } else {
      try {
        key = await importKey(b64decode(location.hash.slice(1)));
      } catch (e) {
        return alert('Wrong secret key');
      }
    }
    let message;
    try {
      message = await decryptRawEnvelope(rawEnvelope, key);
    } catch (e) {
      return alert('Wrong password or key');
    }
    messageElement.value = message;
    form.querySelector('label[for=message]').innerText = 'Message';
    disableInteraction(form);
  } else {
    alert('Error: Message not found');
  }
}

function disableInteraction(form) {
  form.elements.namedItem('message').readonly = true;
  form.querySelector('[type=submit]').disabled = true;
}

async function main() {
  const form = document.forms.namedItem('letter');

  if (location.pathname == '/') {
    form.addEventListener('submit', onGetLink);
  } else {
    const messageElement = form.elements.namedItem('message');
    messageElement.readOnly = true;
    messageElement.value = location.href;
    form.querySelector('label[for=message]').innerText = 'Link';
    form.querySelector('input[type=submit]').value = 'Get and Delete Message';
    form.addEventListener('submit', onGetMessage);
  }
}

document.addEventListener('DOMContentLoaded', main);
JS
js_hash = hash js

html = <<-HTML
<!doctype html>
<html lang="en">
  <head>
    <title>plic</title>
    <meta name="description"
      content="Send one-time secret messages securely with plic.">
    <meta name="viewport" content="initial-scale=1">
    <style>#{css}</style>
    <script>#{js}</script>
  </head>
  <body>
    <main>
      <h1 title="envelope in Romanian">plic</h1>
      <form name="letter" method="POST">
        <label for="message">Message</label>
        <br>
        <textarea id="message" rows="10" cols="50"
          maxlength="980" required></textarea>
        <br><br>
        <label for="password">Password (optional)</label>
        <input id="password" type="password" minlength="8">
        <br><br>
        <input type="submit" value="Get Link">
      </form>
      <br>
      Use plic to send a one-time secret message.
      <br><br>
      <details>
        <summary>How it works</summary>
        <ol>
          <li>A secure, secret key is generated in the browser.</li>
          <li>The key is used to encrypt the message.</li>
          <li>The encrypted message is then sent to the server.</li>
          <li>A link is generated by combining the tag obtained from the
            encryption process and the secret key.</li>
          <li>The secret key is attached to the hash portion of the URL which
            is never sent to the server.</li>
          <li>When a link is opened, the encrypted message is simultaneously
            retrieved and deleted from the server.</li>
          <li>The secret key stored in the URL is used to decrypt the encrypted
            data and the message is displayed.</li>
        </ol>
        Technical details along with source code are available at
        github.com/mohd-akram/plic.
      </details>
    </main>
  </body>
</html>
HTML

port = 8080
db_path = "data.db"

OptionParser.parse! do |parser|
  parser.banner = "usage: plic [options]"
  parser.on("--port port", "Server port") { |p| port = p.to_i }
  parser.on("--db path", "SQLite database file path") do |path|
    db_path = path
  end
  parser.on("-h", "--help", "Show this help") { puts parser }
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

  if !/^\/[A-Za-z0-9-_]*$/.match(path)
    not_found context
    next
  end

  case context.request.method
  when "GET"
    if path != "/"
      context.response.headers["X-Robots-Tag"] = "noindex"
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
          size = part.body.read body
          if part.body.read_byte.nil?
            data = body[0, size]
            tag = data[size - 16, 16]
            id = Base64.urlsafe_encode tag, padding: false
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
            "select data from envelopes where id = ?", id, &.read(Bytes)
        rescue ex : DB::Error
        else
          db.exec "delete from envelopes where id = ?", id
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
  begin
    db.exec (
      "create table envelopes (" \
      "  id text primary key," \
      "  data blob not null," \
      "  created timestamp default current_timestamp" \
      ") without rowid"
    )
  rescue ex : SQLite3::Exception
  end
end

server.bind_tcp port
puts "Listening on http://127.0.0.1:#{port}"
server.listen

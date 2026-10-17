require 'openssl'
require 'base64'
require 'securerandom'

module OclViyar

  # Port of SJCL's sjcl.encrypt(password, text) with its default parameters, as used by Bazis2Viyar
  # to write ViyarPro *.project files: PBKDF2-HMAC-SHA256 (10000 iterations, 64-bit salt) -> 128-bit
  # AES key, AES-CCM with a 64-bit tag, no associated data, output as SJCL's JSON string.
  #
  # CCM is built on AES-ECB/CBC so it doesn't depend on the OpenSSL build's CCM support.
  # Pure Ruby (no SketchUp API).
  module Sjcl

    ITER = 10_000
    KEY_BYTES = 16
    TAG_BYTES = 8
    IV_BYTES = 16
    SALT_BYTES = 8

    def self.encrypt(password, plaintext, salt: SecureRandom.random_bytes(SALT_BYTES), iv: SecureRandom.random_bytes(IV_BYTES))
      data = plaintext.encode('UTF-8').b
      key = OpenSSL::PKCS5.pbkdf2_hmac(password.encode('UTF-8'), salt, ITER, KEY_BYTES, OpenSSL::Digest.new('SHA256'))
      ct = ccm_encrypt(key, data, iv.b)
      '{"iv":"' + _b64(iv) + '","v":1,"iter":' + ITER.to_s + ',"ks":' + (KEY_BYTES * 8).to_s + ',"ts":' + (TAG_BYTES * 8).to_s +
        ',"mode":"ccm","adata":"","cipher":"aes","salt":"' + _b64(salt) + '","ct":"' + _b64(ct) + '"}'
    end

    # RFC 3610 CCM without associated data. Like SJCL: the length field size L is the smallest of 2..4
    # that fits the data length, and the nonce is the IV truncated to 15 - L bytes.
    def self.ccm_encrypt(key, data, iv)
      l = 2
      l += 1 while l < 4 && (data.bytesize >> (8 * l)) > 0
      nonce = iv.byteslice(0, 15 - l)

      b0 = [ ((TAG_BYTES - 2) / 2) << 3 | (l - 1) ].pack('C') + nonce + _be(data.bytesize, l)
      padded = data + ("\0" * ((16 - data.bytesize % 16) % 16))
      mac = _aes('aes-128-cbc', key, b0 + padded, "\0" * 16).byteslice(-16, 16)

      blocks = (data.bytesize + 15) / 16
      counters = (0..blocks).map { |i| [ l - 1 ].pack('C') + nonce + _be(i, l) }.join
      stream = _aes('aes-128-ecb', key, counters)
      tag = _xor(mac.byteslice(0, TAG_BYTES), stream.byteslice(0, TAG_BYTES))
      _xor(data, stream.byteslice(16, data.bytesize)) + tag
    end

    def self._aes(name, key, data, iv = nil)
      cipher = OpenSSL::Cipher.new(name)
      cipher.encrypt
      cipher.padding = 0
      cipher.key = key
      cipher.iv = iv if iv
      cipher.update(data) + cipher.final
    end

    def self._be(value, bytes)
      (0...bytes).map { |i| (value >> (8 * (bytes - 1 - i))) & 0xff }.pack('C*')
    end

    def self._xor(a, b)
      a.bytes.zip(b.bytes).map { |x, y| x ^ y }.pack('C*')
    end

    def self._b64(s)
      Base64.strict_encode64(s)
    end

  end

end

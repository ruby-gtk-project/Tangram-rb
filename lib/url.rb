# frozen_string_literal: true

require 'gobject-introspection'

# Soup carries the public-suffix lookup the same-site test needs. There is no
# ruby-gnome gem for libsoup 3, so the typelib is loaded straight into a
# module of our own; the generated methods and error classes are the ones the
# C API documents.
module Soup
end
GObjectIntrospection::Loader.load('Soup', Soup)

# Url is the address handling upstream keeps in src/utils.js: turning what the
# user typed into a URL, deciding whether two URLs belong to the same site,
# and deciding whether a tab may navigate to an address itself or has to hand
# it to the browser.
#
# Ported from upstream's src/utils.js, with its test file src/utils.test.js
# ported alongside it in spec/url_spec.rb.
#
# Upstream reaches for GLib's URI parser and `g_hostname_to_ascii`. Neither is
# bound in ruby-gnome, so the small part of each this app needs — the scheme
# and host of an absolute URI, and the IDNA/punycode form of a host — is here
# instead. The public-suffix lookup is still libsoup's, which is the part that
# would be wrong to approximate.
module Url
  SCHEMES = %w[http https].freeze

  # RFC 3986, section 3: scheme ":" ["//" authority] rest.
  URI_PATTERN = %r{
    \A
    (?<scheme>[a-zA-Z][a-zA-Z0-9+.\-]*)
    :
    (?://(?<authority>[^/?\#]*))?
    (?<rest>.*)
    \z
  }x

  # The punycode parameters of RFC 3492, section 5.
  PUNYCODE_BASE = 36
  PUNYCODE_TMIN = 1
  PUNYCODE_TMAX = 26
  PUNYCODE_SKEW = 38
  PUNYCODE_DAMP = 700
  PUNYCODE_INITIAL_BIAS = 72
  PUNYCODE_INITIAL_N = 128
  PUNYCODE_PREFIX = 'xn--'

  # The three failures that mean "there is no base domain to compare", rather
  # than "the lookup went wrong": an IP address, a host that is itself a
  # public suffix, and a host with no dot in it.
  NO_BASE_DOMAIN_ERRORS = [
    Soup::TLDError::IsIpAddress,
    Soup::TLDError::NotEnoughDomains,
    Soup::TLDError::NoBaseDomain,
  ].freeze

  class << self
    # Implements https://web.dev/same-site-same-origin/ — the test upstream
    # uses to decide whether a tab stays inside the web app or hands the
    # address to the browser.
    def same_site?(first, second)
      [host(first), host(second)].then do |one, two|
        if one == false || two == false
          # Not an absolute URI: upstream refuses rather than compares.
          false
        elsif one.nil? || two.nil? || one.empty? || two.empty?
          # An address with no host at all, such as about:blank, is the same
          # site as itself and nothing else.
          one == two
        else
          same_base_domain?(one, two)
        end
      end
    end

    # What the user typed, turned into an http(s) URL, or nil when it cannot
    # be one.
    def normalize(string)
      String(string || '').strip.then do |text|
        if text.empty?
          nil
        else
          normalize_absolute(absolute(text))
        end
      end
    end

    # Whether the tab may follow the address itself. A tab still being set up
    # may go anywhere — the user is browsing for the web app's address. One
    # that has been added is pinned to its own site, and anything else belongs
    # in the browser.
    #
    # Upstream's `isUrlAllowedForNavigation` reads the mode off the web view;
    # here the caller passes it, so this stays the pure URL question it is.
    def allowed_for_navigation?(current_url:, request_url:, temporary:)
      if temporary
        true
      else
        same_site?(current_url, request_url)
      end
    end

    # The host of an absolute URI, lowercased and without userinfo, port or
    # the brackets around an IPv6 literal. nil when there is no host, and
    # false when the string is not an absolute URI at all.
    def host(string)
      URI_PATTERN.match(String(string || '')).then do |match|
        if match
          host_of(match[:authority])
        else
          false
        end
      end
    end

    # A host in its ASCII form: every label that is not already ASCII
    # punycoded, the way `g_hostname_to_ascii` returns it.
    def to_ascii(host)
      host.downcase.split('.', -1).map { |label| ascii_label(label) }.join('.')
    end

    private

      def same_base_domain?(one, two)
        [to_ascii(one), to_ascii(two)].then do |first, second|
          if first.empty? || second.empty?
            false
          else
            base_domain(first) == base_domain(second)
          end
        end
      end

      # The registrable domain, or the host itself when it has none: an IP
      # address, a public suffix such as github.io, or a single label such as
      # localhost all compare as themselves.
      def base_domain(host)
        Soup.tld_get_base_domain(host)
      rescue *NO_BASE_DOMAIN_ERRORS
        host
      end

      def absolute(text)
        if text.start_with?('http')
          text
        else
          "http://#{text}"
        end
      end

      def normalize_absolute(text)
        URI_PATTERN.match(text).then do |match|
          if usable?(match)
            "#{match[:scheme].downcase}://#{match[:authority]}#{match[:rest]}"
          end
        end
      end

      def usable?(match)
        !match.nil? &&
          SCHEMES.include?(match[:scheme].downcase) &&
          usable_authority?(match[:authority])
      end

      # An http(s) address needs a host, and a port if it carries one has to
      # be a number. The pattern above is deliberately lenient — `host` has to
      # read the authority out of addresses this port does not handle, such as
      # `about:blank` — so this is where an address the user typed is turned
      # down. It stands in for the parse `g_uri_parse` would refuse: upstream
      # hands "ftp://example.org" to it as "http://ftp://example.org", whose
      # empty port makes it fail, and so the address comes to nothing.
      def usable_authority?(authority)
        strip_port(authority.to_s.split('@').last.to_s).then do |host|
          !host.empty? && usable_port?(authority.to_s)
        end
      end

      def usable_port?(authority)
        port = authority[/\A(?:\[[^\]]*\]|[^:]*):(.*)\z/, 1]

        port.nil? || port.match?(/\A\d+\z/)
      end

      def host_of(authority)
        if authority.nil?
          nil
        else
          strip_port(authority.split('@').last.to_s).downcase
        end
      end

      def strip_port(host)
        if host.start_with?('[')
          host[/\A\[([^\]]*)\]/, 1].to_s
        else
          host.split(':').first.to_s
        end
      end

      def ascii_label(label)
        if label.ascii_only?
          label
        else
          "#{PUNYCODE_PREFIX}#{punycode(label)}"
        end
      end

      # RFC 3492, section 6.3, without the overflow checks a 32-bit
      # implementation needs.
      def punycode(label)
        codepoints = label.codepoints
        basic = codepoints.select { |codepoint| codepoint < PUNYCODE_INITIAL_N }
        output = basic.map { |codepoint| codepoint.chr(Encoding::UTF_8) }

        unless basic.empty?
          output << '-'
        end

        encode_extended(codepoints, basic.length, output)
        output.join
      end

      def encode_extended(codepoints, basic_length, output)
        n = PUNYCODE_INITIAL_N
        delta = 0
        bias = PUNYCODE_INITIAL_BIAS
        handled = basic_length

        while handled < codepoints.length
          m = codepoints.select { |codepoint| codepoint >= n }.min
          delta += (m - n) * (handled + 1)
          n = m

          codepoints.each do |codepoint|
            if codepoint < n
              delta += 1
            end

            if codepoint == n
              delta = encode_codepoint(delta, bias, output)
              bias = adapt(delta, handled + 1, handled == basic_length)
              delta = 0
              handled += 1
            end
          end

          delta += 1
          n += 1
        end

        output
      end

      # Writes one extended codepoint's delta as a variable-length integer and
      # answers the delta it consumed, so the caller can adapt the bias.
      def encode_codepoint(delta, bias, output)
        q = delta
        k = PUNYCODE_BASE
        t = threshold(k, bias)

        while q >= t
          output << digit(t + ((q - t) % (PUNYCODE_BASE - t)))
          q = (q - t) / (PUNYCODE_BASE - t)
          k += PUNYCODE_BASE
          t = threshold(k, bias)
        end

        output << digit(q)
        delta
      end

      def threshold(k, bias)
        if k <= bias + PUNYCODE_TMIN
          PUNYCODE_TMIN
        elsif k >= bias + PUNYCODE_TMAX
          PUNYCODE_TMAX
        else
          k - bias
        end
      end

      def adapt(delta, count, first_time)
        scaled = scale(delta, first_time)
        scaled += scaled / count
        k = 0

        while scaled > ((PUNYCODE_BASE - PUNYCODE_TMIN) * PUNYCODE_TMAX) / 2
          scaled /= PUNYCODE_BASE - PUNYCODE_TMIN
          k += PUNYCODE_BASE
        end

        k + (((PUNYCODE_BASE - PUNYCODE_TMIN + 1) * scaled) / (scaled + PUNYCODE_SKEW))
      end

      def scale(delta, first_time)
        if first_time
          delta / PUNYCODE_DAMP
        else
          delta / 2
        end
      end

      # 0..25 are 'a'..'z' and 26..35 are '0'..'9'.
      def digit(value)
        if value < 26
          (value + 'a'.ord).chr
        else
          (value - 26 + '0'.ord).chr
        end
      end
  end
end

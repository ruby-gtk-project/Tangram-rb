# frozen_string_literal: true

require 'url'

# Ported from upstream's src/utils.test.js, whose assertions are all about
# `isSameSite`. Each `it` below is one of upstream's `assert.is` lines, in
# upstream's order, with upstream's two comments kept where they explain why a
# pair is expected to differ.
#
# The two blocks after it are not upstream's: `normalizeURL` and
# `isUrlAllowedForNavigation` are exported from the same file and have no
# upstream test, and the port's own address handling is worth pinning down.
RSpec.describe Url do
  describe '.same_site?' do
    same_site = [
      ['https://github.com', 'https://github.com'],
      ['https://github.com', 'http://github.com'],
      ['https://github.com:123', 'http://github.com:567/foobar'],
      ['https://foo.github.com', 'https://github.com'],
      ['https://foo.github.com', 'https://bar.github.com'],
      [
        'https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]',
        'https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]',
      ],
      ['https://192.0.2.235', 'https://192.0.2.235'],
      ['https://localhost', 'https://localhost'],
      ['https://github.io', 'https://github.io'],
      ['https://ком.рус', 'https://xn--j1aef.xn--p1acf'],
      ['about:blank', 'about:blank'],
      # кто.рф is not a public suffix, so кто.рф is the base domain of both.
      ['https://foo.кто.рф', 'https://bar.xn--j1ail.xn--p1ai'],
    ]

    cross_site = [
      ['https://foo', 'https://bar'],
      ['https://foo.github.io', 'https://bar.github.io'],
      ['https://foo.github.io', 'https://github.io'],
      # ком.рус is a public suffix, so foo.ком.рус and bar.ком.рус are as
      # unrelated as two different registrable domains.
      ['https://foo.ком.рус', 'https://bar.xn--j1aef.xn--p1acf'],
    ]

    same_site.each do |first, second|
      it "treats #{first} and #{second} as the same site" do
        expect(described_class.same_site?(first, second)).to be(true)
      end
    end

    cross_site.each do |first, second|
      it "treats #{first} and #{second} as different sites" do
        expect(described_class.same_site?(first, second)).to be(false)
      end
    end

    it 'refuses a string that is not an absolute URI' do
      expect(described_class.same_site?('github.com', 'github.com')).to be(false)
    end
  end

  describe '.normalize' do
    it 'leaves an http URL alone' do
      expect(described_class.normalize('http://example.org/x')).to eq('http://example.org/x')
    end

    it 'leaves an https URL alone' do
      expect(described_class.normalize('https://example.org/x')).to eq('https://example.org/x')
    end

    it 'assumes http for a bare host' do
      expect(described_class.normalize('example.org')).to eq('http://example.org')
    end

    it 'keeps the port and the path of a bare host' do
      expect(described_class.normalize('example.org:8080/app')).to eq('http://example.org:8080/app')
    end

    it 'trims what the user typed' do
      expect(described_class.normalize('  example.org  ')).to eq('http://example.org')
    end

    it 'has nothing to offer for an empty string' do
      expect(described_class.normalize('')).to be_nil
    end

    it 'has nothing to offer for nil' do
      expect(described_class.normalize(nil)).to be_nil
    end

    it 'refuses a scheme that is not http or https' do
      expect(described_class.normalize('httpx://example.org')).to be_nil
    end

    # Upstream prepends "http://" to anything that does not already start with
    # "http", so another scheme arrives at the parser as
    # "http://ftp://example.org" — which has an empty port and comes to
    # nothing.
    it 'refuses another scheme, which it has prefixed into nonsense' do
      expect(described_class.normalize('ftp://example.org')).to be_nil
    end

    it 'refuses an address with no host' do
      expect(described_class.normalize('http://')).to be_nil
    end

    it 'refuses a port that is not a number' do
      expect(described_class.normalize('example.org:http')).to be_nil
    end
  end

  describe '.allowed_for_navigation?' do
    it 'lets a tab still being set up go anywhere' do
      allowed = described_class.allowed_for_navigation?(
        current_url: 'https://example.org/',
        request_url: 'https://elsewhere.test/',
        temporary:   true,
      )

      expect(allowed).to be(true)
    end

    it 'keeps an added tab on its own site' do
      allowed = described_class.allowed_for_navigation?(
        current_url: 'https://example.org/',
        request_url: 'https://elsewhere.test/',
        temporary:   false,
      )

      expect(allowed).to be(false)
    end

    it 'lets an added tab move within its own site' do
      allowed = described_class.allowed_for_navigation?(
        current_url: 'https://example.org/',
        request_url: 'https://www.example.org/app',
        temporary:   false,
      )

      expect(allowed).to be(true)
    end
  end
end

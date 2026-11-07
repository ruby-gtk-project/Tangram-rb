# frozen_string_literal: true

require 'gettext'

# Translations wires every widget that shows the user a string to upstream's
# own message catalogue — `po/re.sonny.Tangram.pot`, `po/LINGUAS`, `po/*.po` —
# reused unchanged under its own domain. The port adds no catalogue of its
# own: every `_()`/`p_()` call elsewhere in `lib/` has to carry a msgid that
# is byte-identical to the one upstream's translators already worked from, or
# the lookup misses and the 21 languages upstream ships do not reach it.
#
# `bindtextdomain` binds to whatever includes this module, not to the
# process, so every class with a translated string includes `Translations`
# rather than calling `GetText` on its own.
module Translations
  include GetText

  DOMAIN = 're.sonny.Tangram'
  LOCALE_DIR = File.expand_path('../locale', __dir__)

  bindtextdomain(DOMAIN, path: LOCALE_DIR)
end

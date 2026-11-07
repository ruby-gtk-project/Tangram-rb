#!/usr/bin/env ruby
# frozen_string_literal: true

# A minimal, isolated reproduction of the segfault documented in
# `lib/web_view.rb`'s class comment (the paragraph on
# `initialize-notification-permissions`): calling
# `WebKit::WebContext#initialize_notification_permissions` with a non-empty
# `GList` of `WebKit::SecurityOrigin` crashes the process every time, because
# of a bug in `gobject-introspection`'s own argument marshalling (see the
# comment in `lib/web_view.rb` for the exact function and the reasoning).
#
# This script is deliberately NOT wired into `test/run_all.rb` or any other
# part of the gate: the whole point of running it is that the process
# crashes, which is not something a test suite can assert on, only cause.
# It exists so the crash — the exact command, the exact backtrace — can be
# cited verbatim when filing this against ruby-gnome/gobject-introspection,
# and re-run after any bump of that gem to see whether the bug is still
# there.
#
#   nix develop --command xvfb-run -a ruby test/webkit_notification_permissions_segfault_repro.rb
#
# Expected result: a `[BUG] Segmentation fault` from the Ruby interpreter
# itself, from inside `gobject-introspection/loader.rb`'s `invoke`, never
# reaching "survived (unexpectedly — bug may be fixed upstream)".

require 'gobject-introspection'

module WebKit
end
GObjectIntrospection::Loader.load('WebKit', WebKit)

context = WebKit::WebContext.new
origin = WebKit::SecurityOrigin.new('https', 'example.com', 443)

puts "constructed #{origin} — about to pass it in a non-empty GList"
STDOUT.flush

context.initialize_notification_permissions([origin], [])

puts 'survived (unexpectedly — bug may be fixed upstream)'

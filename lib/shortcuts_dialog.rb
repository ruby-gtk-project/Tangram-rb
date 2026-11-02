# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts, behind the main menu's
# "Keyboard Shortcuts" and <Control>question.
#
# Ported from upstream's src/shortcuts.blp, which is a GtkShortcutsWindow with
# one section and three groups. GtkShortcutsWindow has been deprecated since
# GTK 4.18 and its Ruby binding is unusable (`GtkWindow is not subtype of
# GtkShortcutsWindow`), so this is the Adwaita replacement: upstream's three
# groups become three Adw.ShortcutsSections, carrying the same titles,
# the same items, in the same order, with the same accelerators.
#
# Two of upstream's items are gestures rather than accelerators
# (`gesture_two_finger_swipe_right` and `_left`). Adw.ShortcutsItem has no
# gesture type, so each is listed with the gesture named in its subtitle.
class ShortcutsDialog
  SECTIONS = [
    [
      'Tabs',
      [
        ['Open tabs overview', '<Alt>T'],
        ['Switch to the next tab', '<Control>Page_Down <Control>Tab'],
        ['Switch to the previous tab', '<Control>Page_Up <Shift><Control>Tab'],
        # Upstream writes this one accelerator as "<Ctrl>Home"; every other
        # one in the file spells the modifier out, and so does this.
        ['Switch to the first tab', '<Control>Home'],
        ['Switch to the last tab', '<Control>End'],
        ['Move current tab backward', '<Control><Shift>Page_Up'],
        ['Move current tab forward', '<Control><Shift>Page_Down'],
        ['Move current tab at the start', '<Control><Shift>Home'],
        ['Move current tab at the end', '<Control><Shift>End'],
        ['Switch to tabs 1⋯10', '<Alt>1...0'],
      ],
    ],
    [
      'Navigation',
      [
        ['Go to homepage', '<Alt>Home'],
        ['Reload current page', 'F5 <Control>R'],
        ['Reload bypassing cache', '<Control><Shift>R <Shift>F5'],
        ['Stop loading current page', 'Escape'],
        ['Go back to the previous page', '<Alt>Left'],
        ['Go forward to the next page', '<Alt>Right'],
        ['Focus the address bar', '<Control>L'],
      ],
    ],
    [
      'General',
      [
        ['Quit', '<Control>Q'],
        ['Shortcuts', '<Control>question'],
        ['Toggle inspector', '<Control><Shift>I'],
      ],
    ],
  ].freeze

  # The two gesture rows, which sit at the end of upstream's Navigation group.
  GESTURES = [
    ['Go back to the previous page', 'Two-finger swipe right'],
    ['Go forward to the next page', 'Two-finger swipe left'],
  ].freeze

  GESTURE_SECTION = 'Navigation'

  def build
    @build ||= dialog.tap do |shortcuts|
      SECTIONS.each do |title, items|
        shortcuts.add(section(title, items))
      end
    end
  end

  def present(parent) = build.present(parent)

  def dialog = @dialog ||= Adwaita::ShortcutsDialog.new

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }

        if title == GESTURE_SECTION
          GESTURES.each { |label, gesture| section.add(gesture_item(label, gesture)) }
        end
      end
    end

    # Positional, not keyword, arguments — even though the error a no-argument
    # new raises advertises the signatures as "title: utf8, accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)

    def gesture_item(label, gesture)
      item(label, '').tap { |shortcut| shortcut.subtitle = gesture }
    end
end

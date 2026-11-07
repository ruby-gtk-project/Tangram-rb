# frozen_string_literal: true

# One upstream source file maps to one file here, and this is the list of
# them. Requiring "tangram" loads the port: the support and model layer
# first, then the widgets built on it, then the application itself.
require_relative 'translations'
require_relative 'env'
require_relative 'settings'
require_relative 'state'
require_relative 'url'
require_relative 'instances'
require_relative 'web_view'
require_relative 'web_app_info'
require_relative 'main_menu'
require_relative 'about_dialog'
require_relative 'shortcuts_dialog'
require_relative 'delete_tab_dialog'
require_relative 'instance_dialog'
require_relative 'tabs'
require_relative 'view_tabs'
require_relative 'view_new'
require_relative 'shortcuts'
require_relative 'actions'
require_relative 'window'
require_relative 'tangram/application'

# dmgbuild settings for the Desktop Buddy install window (used by ./build-app.sh --share).
# Background: dmg/background.tiff (regenerate with dmg/make-background.py). Window 640 × 440 pt.
import os

application = defines.get("app", "dist/Desktop Buddy.app")  # noqa: F821 (dmgbuild provides `defines`)
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"                 # the mounted disk's icon

background = "dmg/background.tiff"
window_rect = ((200, 140), (640, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 112
icon_locations = {appname: (170, 215), "Applications": (470, 215)}

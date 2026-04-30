#!/bin/bash
set -e

# Enable two-finger swipe to back/forward in Chrome via desktop entry

echo "→ Creating local applications directory..."
mkdir -p ~/.local/share/applications

echo "→ Copying Chrome desktop entries..."
for file in /usr/share/applications/{google-chrome.desktop,com.google.Chrome.desktop}; do
    if [[ -f "$file" ]]; then
        cp "$file" ~/.local/share/applications/
        fname=$(basename "$file")
        echo "→ Patching $fname ..."
        sed -i 's|Exec=.*google-chrome-stable|Exec=/usr/bin/google-chrome-stable --enable-features=TouchpadOverscrollHistoryNavigation|g' ~/.local/share/applications/"$fname"
    fi
done

echo "→ Updating desktop database..."
update-desktop-database ~/.local/share/applications/ >/dev/null 2>&1 || true

echo "✅ Done! Restart Chrome completely to apply changes."
echo "   (If gestures don’t work, try adding --ozone-platform=wayland after the feature flag if you’re on Wayland.)"

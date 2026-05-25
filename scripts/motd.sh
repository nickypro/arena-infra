#!/usr/bin/env bash
chmod -x /etc/update-motd.d/10-help-text 
chmod -x /etc/update-motd.d/50-motd-news
chmod -x /etc/update-motd.d/60-unminimize

filename=/etc/update-motd.d/20-arena

echo '#!/bin/sh' > $filename
echo '' >> $filename
echo 'if [ -x /usr/bin/figlet ]; then' >> $filename
echo '    /usr/bin/figlet ARENA' >> $filename
echo 'else' >> $filename
echo '    echo "";' >> $filename
echo 'fi' >> $filename
echo "echo 'You are on ARENA machine $MACHINE_NAME';" >> $filename
echo 'echo "";' >> $filename

chmod +x $filename


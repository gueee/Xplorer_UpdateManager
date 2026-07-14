#!/bin/bash
# Free /dev/ttyAMA0 so Klipper can own the Pi5<->M8P v2 UART link.
# Needed after flashing the M8P with a USART1 (serial, non-USB) Klipper build
# and wiring Pi GPIO14/15 (TXD/RXD) to the M8P USART1 pins.
# Run on the Pi with: sudo bash ~/free_uart_for_klipper.sh
set -e
echo "==> Stopping + masking serial login console on ttyAMA0"
systemctl stop serial-getty@ttyAMA0.service 2>/dev/null || true
systemctl disable serial-getty@ttyAMA0.service 2>/dev/null || true
systemctl mask serial-getty@ttyAMA0.service 2>/dev/null || true

echo "==> Removing kernel serial console from cmdline.txt"
CMD=/boot/firmware/cmdline.txt
cp "$CMD" "$CMD.bak" 2>/dev/null || true
sed -i "s/console=serial0,[0-9]* //g; s/console=ttyAMA0,[0-9]* //g" "$CMD"
echo "--- new cmdline.txt ---"; cat "$CMD"

echo "==> Restarting Klipper"
systemctl restart klipper 2>/dev/null || true
echo "DONE. Reboot recommended so cmdline.txt takes effect: sudo reboot"

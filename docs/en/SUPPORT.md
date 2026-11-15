# MicRelay support

[Privacy policy](PRIVACY.md) / [Source code](https://github.com/ryuya0124/MicRelay) / [License notices](../../THIRD_PARTY_NOTICES.md)

1. Connect headphones or an HDMI device and tap **Refresh connections and microphones** to allow microphone access.
2. Choose an input microphone. For USB and Bluetooth devices, confirm that the connected output is headphones if prompted.
3. Tap **Start monitoring**. Monitor gain is separate from the device’s system volume.
4. Open **Equalizer** to compare the live input and processed spectra while listening. Band stop attenuates the range between the lower and upper frequencies; band pass passes that range. Turning EQ off bypasses filter processing.

If you cannot hear audio, check microphone permission, the selected input, output confirmation, monitor gain, and system volume. Another app using the microphone exclusively may interrupt monitoring. Bluetooth latency depends on the hardware and connection mode.

The app supports Japanese and English and follows the OS language preference. Use the app’s language setting in iOS or iPadOS Settings to select a different supported language.

Report bugs and requests through [GitHub Issues](https://github.com/ryuya0124/MicRelay/issues). Include your device model, OS version, audio hardware, and steps to reproduce the problem. Audio, personal information, and credentials are not needed.

Enable **Wind noise reduction** in the volume and tone section to reduce low-frequency rumble. Raising the low-cut frequency also reduces voice bass. It works independently of EQ and is included in settings backups. It uses no look-ahead audio buffer.

Keep the audio mode on **Automatic** for normal use. **Fully manual** lets you choose a frame count and sample rate from dropdown menus. **Verify and apply** tests the settings silently and saves them only if the actual values match and input is stable. Failed changes show the reason and restore your previous settings. During monitoring, requested and actual values appear side by side. If saved manual settings cannot be used after a device or connection change, monitoring stops; select Automatic or adjust the manual settings.

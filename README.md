# Digital Footprint Explorer (DFE) 🌿📱

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-blue)](#)
[![Institution](https://img.shields.io/badge/Developed%20at-ZHAW-red)](https://www.zhaw.ch)

> **Make the invisible environmental impacts of your digital activities visible.**

The **Digital Footprint Explorer (DFE)** is a mobile application developed at the **Zurich University of Applied Sciences (ZHAW)**. It translates unseen digital resource consumption—such as data streaming, messaging, social media usage, and AI processing—into intuitive, emotionally engaging eco-feedback.

---

## 📌 Overview

While modern digital activities feel virtual and weightless, they rely on energy-intensive infrastructure: data centers, network transmission lines, and device manufacturing. DFE addresses this disconnect by transforming abstract mobile data metrics into a tangible metaphor: **a living virtual garden**.

* **Flourishing State:** When your digital footprint remains low, your garden thrives with vibrant plants.
* **Deteriorating State:** High data-intensive consumption (such as high-definition video streaming) gradually degrades the virtual environment.

<img src="docs/images/widget.png" alt="Digital Footprint Explorer widget" width="300"/>

---

## ✨ Key Features

- **🌱 Virtual Eco-System Metaphor:** Real-time visual feedback represented via a dynamic virtual garden and desktop widget.
- **📊 Activity Classification:** Tracks and categorizes data usage from common mobile activities.
- **💡 Educational Insights:** Learn how manufacturing, data transport, and server energy contribute to overall $\text{CO}_2\text{e}$ emissions.
- **🔒 Privacy-First Architecture:** Local data processing ensures mobile network tracking stays strictly on your device.

---

## 🔒 Privacy & Data Safety
The Digital Footprint Explorer respects user privacy:
- No personal usage data, browsing history, or message content is inspected or stored outside your local device.
- Network traffic statistics are read exclusively at the aggregate system layer to compute the visual representation.

--

## Installing the App

For Android users, the app is available on the Google Play Store:

[![Get it on Google Play](https://play.google.com/intl/en_us/badges/images/generic/en_badge_web_generic.png)](https://play.google.com/store/apps/details?id=ch.zhaw.digitalfootprintexplorer&hl=en)

--

## 🤝 Contributing
Contributions are welcome! If you would like to submit bug fixes, feature requests, or scientific improvements:
1. Fork the Project.
2. Create your Feature Branch (git checkout -b feature/AmazingFeature).
3. Commit your Changes (git commit -m 'Add some AmazingFeature').
4. Push to the Branch (git push origin feature/AmazingFeature).
5. Open a Pull Request.

## iOS app

The native iPhone app is in `DigitalFootprintExplorer/iosApp/`. It reuses the shared emissions model and includes the daily garden, local history, garden widgets and optional morning notices. Usage comes from Screen Time where Apple permits access; carbon and traffic remain estimates. The app requires iOS 26.4 or later.

Open `DigitalFootprintExplorer/iosApp/iosApp.xcodeproj` in Xcode 27.1 with the iOS 27 SDK. The app runs on iOS 26.4 or later. Choose the `iosApp-ScreenTime` scheme and `ScreenTimeDebug` configuration. Physical-device testing also needs your team's signing settings and the required Apple capabilities.

For setup, signing and the automatic-input limits, see the [iOS guide](DigitalFootprintExplorer/iosApp/README.md). Run the controlled simulator checks from the repository root with:

```sh
bash DigitalFootprintExplorer/iosApp/scripts/ios-check.sh
```

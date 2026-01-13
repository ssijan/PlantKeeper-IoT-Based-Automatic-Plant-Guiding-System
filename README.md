Markdown

# 🪴 Plant Keeper: Smart Indoor Plant Monitoring System

**Plant Keeper** is an IoT-based system designed to ensure your indoor plants thrive. Using an **ESP32**, the system monitors environmental data, displays it locally on an **LCD**, logs it to the **ThingSpeak Cloud**, and provides a **Flutter** mobile application for remote monitoring and control.

---

## 🌟 Key Features
* **Real-time Monitoring:** Track Temperature, Humidity, Light Intensity, and Soil Moisture.
* **Instant Local Display:** View sensor data immediately on a 16x2 LCD monitor.
* **Remote Control:** Switch indoor room lights and water pumps ON/OFF via the mobile app.
* **Cloud Data Logging:** All sensor records are stored in **ThingSpeak** for historical analysis.
* **Notifications:** Stay updated with records and alerts sent directly to your phone.
* **Cross-Platform App:** A sleek, modern UI built using **Flutter**.

---

## 🛠️ Hardware Components
* **Microcontroller:** ESP32 (Wi-Fi enabled)
* **Display:** LCD 16x2 with I2C Module
* **Sensors:** * DHT11/22 (Temperature & Humidity)
    * LDR (Light Intensity)
    * Soil Moisture Sensor
* **Actuators:**
    * Relay Module (for Room Light control)
    * Submersible Water Pump (for watering)

---

## ☁️ Cloud & Software Stack
* **Cloud Storage:** [ThingSpeak](https://thingspeak.com/) (IoT Analytics)
* **Mobile Framework:** [Flutter](https://flutter.dev) (Dart)
* **Communication:** HTTP Protocol for Data Fetching

---

## 📁 Project Structure
```text
.
├── lib/                  # Flutter source code
│   ├── main.dart         # Entry point
│   ├── screens/          # App UI and Dashboards
│   └── services/         # ThingSpeak API integration
├── assets/               # App icons and images
├── pubspec.yaml          # Flutter dependencies
└── .gitignore            # Files excluded from GitHub
⚙️ Setup & Installation
1. Mobile App
Clone the repository:

Bash

git clone [https://github.com/ssijan/PlantKeeper-IoT-Based-Automatic-Plant-Guiding-System.git](https://github.com/ssijan/PlantKeeper-IoT-Based-Automatic-Plant-Guiding-System.git)
Navigate to the project directory:

Bash

cd "IoT app/IoT app"
Install dependencies:

Bash

flutter pub get
Run the app:

Bash

flutter run
2. ThingSpeak Setup
Create a New Channel on ThingSpeak.

Enable 4 Fields (Temp, Humidity, Light, Soil).

Copy your Channel ID and Read/Write API Keys into your ESP32 code and Flutter app.

🤝 Contributing
Contributions, issues, and feature requests are welcome!


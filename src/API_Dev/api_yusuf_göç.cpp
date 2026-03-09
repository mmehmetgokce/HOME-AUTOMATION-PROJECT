//...
//...
//...
//...
//...

// =============================================================
// [R2.3] APPLICATION PROGRAMMING INTERFACE (API)
// Responsible: YUSUF GOC
// =============================================================

// --- [R2.3-1] Base Class Definition ---
// Defines the abstract structure for system connections as shown in UML.
class HomeAutomationSystemConnection {
protected:
    int comPort;
    int baudRate;
    SerialPort serial;

public:
    HomeAutomationSystemConnection() : comPort(0), baudRate(9600) {}

    // [R2.3-1] Open connection via UART
    bool open() { return serial.connect(comPort, baudRate); }

    // [R2.3-1] Close connection
    bool close() { serial.disconnect(); return true; }

    // [R2.3-1] Abstract method to update member data from board
    virtual void update() = 0;

    // [R2.3-1] Setters for connection parameters
    void setComPort(int port) { this->comPort = port; }
    void setBaudRate(int rate) { this->baudRate = rate; }
};

// --- [R2.3-1] Board #1 Class (Air Conditioner) ---
// Encapsulates communication with the Air Conditioner Board.
class AirConditionerSystemConnection : public HomeAutomationSystemConnection {
private:
    float desiredTemperature;
    float ambientTemperature;
    int fanSpeed;

public:
    AirConditionerSystemConnection() {
        desiredTemperature = 0.0;
        ambientTemperature = 0.0;
        fanSpeed = 0;
    }

    // [R2.3-1] Update: Sends GET commands and updates private members
    void update() override {
        if (!serial.isConnected()) return;
        unsigned char valInt, valFrac;

        serial.flush();

        // Protocol: Get Desired Temp (0x02 Int, 0x01 Frac)
        serial.writeByte(0x02); Sleep(150); valInt = serial.readByte();
        serial.writeByte(0x01); Sleep(150); valFrac = serial.readByte();
        desiredTemperature = (float)valInt + ((float)valFrac / 10.0f);

        // Protocol: Get Ambient Temp (0x04 Int, 0x03 Frac)
        serial.writeByte(0x04); Sleep(150); valInt = serial.readByte();
        serial.writeByte(0x03); Sleep(150); valFrac = serial.readByte();
        ambientTemperature = (float)valInt + ((float)valFrac / 10.0f);

        // Protocol: Get Fan Speed (0x05)
        serial.writeByte(0x05); Sleep(150);
        fanSpeed = serial.readByte();
    }

    // [R2.3-1] Set Desired Temp: Sends SET command to board
    bool setDesiredTemp(float temp) {
        if (!serial.isConnected()) return false;
        int tempInt = (int)temp;
        int tempFrac = (int)((temp - tempInt) * 10);

        // Protocol: 11xxxxxx for Int, 10xxxxxx for Frac
        unsigned char cmdInt = 0xC0 | (tempInt & 0x3F);
        serial.writeByte(cmdInt); Sleep(100);

        unsigned char cmdFrac = 0x80 | (tempFrac & 0x3F);
        serial.writeByte(cmdFrac); Sleep(100);
        return true;
    }

    // [R2.3-1] Getters for member data
    float getDesiredTemp() { return desiredTemperature; }
    float getAmbientTemp() { return ambientTemperature; }
    int getFanSpeed() { return fanSpeed; }
};

// --- [R2.3-1] Board #2 Class (Curtain Control) ---
// Encapsulates communication with the Curtain Control Board.
class CurtainControlSystemConnection : public HomeAutomationSystemConnection {
private:
    float curtainStatus;
    float outdoorTemperature;
    float outdoorPressure;
    double lightIntensity;

public:
    CurtainControlSystemConnection() {
        curtainStatus = 0.0;
        outdoorTemperature = 0.0;
        outdoorPressure = 0.0;
        lightIntensity = 0.0;
    }

    // [R2.3-1] Update: Sends GET commands and updates private members
    void update() override {
        if (!serial.isConnected()) return;
        unsigned char valL, valH;

        serial.flush();

        // Protocol: Get Curtain Status (0x02)
        serial.writeByte(0x02); Sleep(150);
        unsigned char rawCurtain = serial.readByte();
        if (rawCurtain > 100) rawCurtain = 100;
        curtainStatus = (float)rawCurtain;

        // Protocol: Get Outdoor Temp (0x04 High, 0x03 Low)
        serial.writeByte(0x04); Sleep(150); valH = serial.readByte();
        serial.writeByte(0x03); Sleep(150); valL = serial.readByte();
        outdoorTemperature = (float)valH + ((float)valL / 10.0f);

        // Protocol: Get Pressure (0x06 High, 0x05 Low)
        serial.writeByte(0x06); Sleep(150); valH = serial.readByte();
        serial.writeByte(0x05); Sleep(150); valL = serial.readByte();
        outdoorPressure = (float)((valH << 8) | valL);

        // Protocol: Get Light (0x08 High)
        serial.writeByte(0x08); Sleep(150); valH = serial.readByte();
        lightIntensity = (double)valH;
    }

    // [R2.3-1] Set Curtain Status: Sends SET command to board
    bool setCurtainStatus(float status) {
        if (!serial.isConnected()) return false;

        int val = (int)status;
        // Protocol: 11xxxxxx for Curtain Status
        unsigned char cmd = 0xC0 | (val & 0x3F);
        serial.writeByte(cmd);
        Sleep(100);
        return true;
    }

    // [R2.3-1] Getters for member data
    float getCurtainStatus() { return curtainStatus; }
    float getOutdoorTemp() { return outdoorTemperature; }
    float getOutdoorPress() { return outdoorPressure; }
    double getLightIntensity() { return lightIntensity; }
};

//...
//...
//...
//...
//...

// --- MAIN (TEST PROGRAM) ---
// Responsible: YUSUF GOC
// [R2.3-2] To test each member functions of classes, test program is written here.
int main() {
    AirConditionerSystemConnection acSys;
    CurtainControlSystemConnection ccSys;

    // PORT CONFIGURATION (User definable)
    int port1 = 3; // Port for Board 1
    int port2 = 5; // Port for Board 2

    // [R2.3-1] Setting up API connections
    acSys.setComPort(port1);
    ccSys.setComPort(port2);

    cout << "Connecting to Board 1 (COM" << port1 << ")... ";
    if (acSys.open()) cout << "OK" << endl; else cout << "FAILED" << endl;

    cout << "Connecting to Board 2 (COM" << port2 << ")... ";
    if (ccSys.open()) cout << "OK" << endl; else cout << "FAILED" << endl;

    Sleep(1000);

    // [R2.4] Main Menu Loop
    while (true) {
        clearScreen();
        cout << "==========================================" << endl;
        cout << "           MAIN MENU" << endl;
        cout << "==========================================" << endl;
        cout << "1. Air Conditioner" << endl;
        cout << "2. Curtain Control" << endl;
        cout << "3. Exit" << endl;
        cout << "==========================================" << endl;
        cout << "Select: ";

        char choice = _getch();

        if (choice == '1') {
            // [R2.4-1] Show Board 1 Data
            // Passing port number to display it dynamically without modifying API class
            showAirConditionerMenu(acSys, port1);
        }
        else if (choice == '2') {
            // [R2.4-1] Show Board 2 Data
            showCurtainMenu(ccSys, port2);
        }
        else if (choice == '3') {
            acSys.close();
            ccSys.close();
            break;
        }
    }
    return 0;
}
/*
 * ============================================================================================
 * PROJECT: HOME AUTOMATION - API
 * SYSTEM: Windows (Uses <windows.h> for Serial Communication)
 *
 * RESPONSIBILITIES:
 *
 * 1. YUSUF GOC (152120221056) - COMPUTER ENGINEERING
 * - [R2.3] API Architecture & Implementation.
 * - [R2.3-1] Implementation of HomeAutomationSystemConnection Base Class.
 * - [R2.3-1] Implementation of AirConditionerSystemConnection Derived Class.
 * - [R2.3-1] Implementation of CurtainControlSystemConnection Derived Class.
 * - [R2.3-2] Main Test Routine & Object Instantiation.
 * - Protocol Data Encapsulation & Parsing Logic.
 *
 * 2. MUHAMMED MEHMET GOKCE (152120221070) - COMPUTER ENGINEERING
 * - Low-Level SerialPort Class Implementation (Windows API Wrapper).
 * - [R2.4] Application Layer & User Interface Design.
 * - [R2.4-1] Menu System Implementation (Console-based).
 * ============================================================================================
 */

#include <iostream>
#include <windows.h>
#include <string>
#include <iomanip>
#include <conio.h>

using namespace std;

// =============================================================
// HELPER CLASS: SERIAL PORT
// Responsible: MUHAMMED MEHMET GOKCE
// Function: Low-level wrapper for Windows Serial Comm API.
// This handles the physical byte transfer required by the API.
// =============================================================
class SerialPort {
private:
    HANDLE hSerial;
    bool connected;
    COMSTAT status;
    DWORD errors;

public:
    SerialPort() : connected(false) {}

    bool connect(int portNumber, int baudRate) {
        string portName = "\\\\.\\COM" + to_string(portNumber);
        hSerial = CreateFileA(portName.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0, NULL, OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL, NULL);

        if (hSerial == INVALID_HANDLE_VALUE) return false;

        DCB dcbSerialParams = { 0 };
        dcbSerialParams.DCBlength = sizeof(dcbSerialParams);

        if (!GetCommState(hSerial, &dcbSerialParams)) return false;

        dcbSerialParams.BaudRate = baudRate;
        dcbSerialParams.ByteSize = 8;
        dcbSerialParams.StopBits = ONESTOPBIT;
        dcbSerialParams.Parity = NOPARITY;

        if (!SetCommState(hSerial, &dcbSerialParams)) return false;

        COMMTIMEOUTS timeouts = { 0 };
        timeouts.ReadIntervalTimeout = 50;
        timeouts.ReadTotalTimeoutConstant = 200;
        timeouts.ReadTotalTimeoutMultiplier = 10;
        timeouts.WriteTotalTimeoutConstant = 50;
        timeouts.WriteTotalTimeoutMultiplier = 10;

        if (!SetCommTimeouts(hSerial, &timeouts)) return false;

        connected = true;
        return true;
    }

    void disconnect() {
        if (connected) {
            CloseHandle(hSerial);
            connected = false;
        }
    }

    bool writeByte(unsigned char data) {
        if (!connected) return false;
        DWORD bytesSend;
        if (!WriteFile(hSerial, &data, 1, &bytesSend, NULL)) return false;
        return true;
    }

    unsigned char readByte() {
        if (!connected) return 0;
        DWORD bytesRead;
        unsigned char buffer = 0;
        ClearCommError(hSerial, &errors, &status);
        ReadFile(hSerial, &buffer, 1, &bytesRead, NULL);
        return buffer;
    }

    bool isConnected() { return connected; }

    void flush() {
        if (!connected) return;
        PurgeComm(hSerial, PURGE_RXCLEAR | PURGE_TXCLEAR);
    }
};

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

// =============================================================
// [R2.4] APPLICATION LAYER
// Responsible: MUHAMMED MEHMET GOKCE
// =============================================================

void clearScreen() { system("cls"); }

// [R2.4-1] Air Conditioner Menu implementation
// Note: 'currentPort' is passed as parameter to maintain strict UML adherence 
// for the class structure (No getComPort method in UML).
void showAirConditionerMenu(AirConditionerSystemConnection& ac, int currentPort) {
    while (true) {
        ac.update(); // [R2.3-1] Update data using API
        clearScreen();
        // [R2.4-1] Display System Data
        cout << "------------------------------------------" << endl;
        cout << "Home Ambient Temperature: " << fixed << setprecision(1) << ac.getAmbientTemp() << " C" << endl;
        cout << "Home Desired Temperature: " << ac.getDesiredTemp() << " C" << endl;
        cout << "Fan Speed: " << ac.getFanSpeed() << " rps" << endl;
        cout << "------------------------------------------" << endl;
        // Display Dynamic Port Info
        cout << "Connection Port: COM" << currentPort << endl;
        cout << "Connection Baudrate: 9600" << endl;
        cout << "------------------------------------------" << endl;
        cout << "              MENU" << endl;
        cout << "1. Enter the desired temperature" << endl;
        cout << "2. Return" << endl;
        cout << "------------------------------------------" << endl;
        cout << "Select: ";

        char choice = _getch();
        if (choice == '1') {
            float newTemp;
            while (true) {
                cout << endl << "Enter Desired Temp (0-63): ";
                cin >> newTemp;

                if (newTemp >= 0 && newTemp <= 63) {
                    break;
                }
                else {
                    cout << "ERROR: Please enter a value between 0 and 63!" << endl;
                }
            }

            ac.setDesiredTemp(newTemp); // [R2.3-1] API Call
            cout << "Sending command..." << endl;
            Sleep(500);
        }
        else if (choice == '2') break;
    }
}

// [R2.4-1] Curtain Control Menu implementation
void showCurtainMenu(CurtainControlSystemConnection& cc, int currentPort) {
    while (true) {
        cc.update(); // [R2.3-1] Update data using API
        clearScreen();
        // [R2.4-1] Display System Data
        cout << "------------------------------------------" << endl;
        cout << "Outdoor Temperature: " << fixed << setprecision(1) << cc.getOutdoorTemp() << " C" << endl;
        cout << "Outdoor Pressure: " << cc.getOutdoorPress() << " hPa" << endl;
        cout << "Curtain Status: " << cc.getCurtainStatus() << " %" << endl;
        cout << "Light Intensity: " << cc.getLightIntensity() << " Lux" << endl;
        cout << "------------------------------------------" << endl;
        // Display Dynamic Port Info
        cout << "Connection Port: COM" << currentPort << endl;
        cout << "Connection Baudrate: 9600" << endl;
        cout << "------------------------------------------" << endl;
        cout << "              MENU" << endl;
        cout << "1. Enter the desired curtain status" << endl;
        cout << "2. Return" << endl;
        cout << "------------------------------------------" << endl;
        cout << "Select: ";

        char choice = _getch();
        if (choice == '1') {
            float newStatus;
            while (true) {
                cout << endl << "Enter Desired Curtain (0-63%): ";
                cin >> newStatus;

                if (newStatus >= 0 && newStatus <= 63) {
                    break;
                }
                else {
                    cout << "ERROR: Please enter a value between 0 and 63!" << endl;
                }
            }

            cc.setCurtainStatus(newStatus); // [R2.3-1] API Call
            cout << "Sending command..." << endl;
            Sleep(500);
        }
        else if (choice == '2') break;
    }
}

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
//...
//...
//...
//...
//...

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

//...
//...
//...
//...
//...

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

//...
//...
//...
//...
//...
#include <iostream>
#include <cstring>
#include <unistd.h>
#include <arpa/inet.h>
#include <string.h>

#include <ctime>
#include <sstream>
#include <iomanip>

#include <fstream>
#include <thread>

// get sensor data from every minutes:
const int minute_interval = 1;

const int num_devices = 1;
const char* devices_ips[] = {
    "192.168.1.6",  // dev ip
    "3",            // number of sensors to read
};

const int server_port = 34677;
const char* request = "GET ?features";

const int buf_size = 4096;

std::string getCurrentDateTime() {
    std::time_t now = std::time(nullptr);
    std::tm* localTime = std::localtime(&now);

    std::ostringstream oss;
    oss << std::put_time(localTime, "%d/%m/%Y;%H:%M");
    return oss.str();
}

std::string getResponse(std::string dev_ip) {
    // Create socket
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "Error creating socket\n";
        return "";
    }

    // Define server address
    sockaddr_in server_addr{};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(server_port);
    if (inet_pton(AF_INET, dev_ip.c_str(), &server_addr.sin_addr) <= 0) {
        std::cerr << "Invalid address or address not supported\n";
        close(sock);
        return "";
    }

    // Connect to server
    if (connect(sock, (sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        std::cerr << "Connection failed\n";
        close(sock);
        return "";
    }

    // Send request
    if (send(sock, request, strlen(request), 0) < 0) {
        std::cerr << "Send failed\n";
        close(sock);
        return "";
    }

    // Receive response
    char buffer[buf_size];
    ssize_t bytes_received = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (bytes_received < 0) {
        std::cerr << "Receive failed\n";
        close(sock);
        return "";
    }

    buffer[bytes_received] = '\0'; // Null-terminate the received data

    std::string response(buffer);
    close(sock);
    return response;
}

std::string getDataString(std::string raw_response, int dev_i) {
    std::string save_string;
    save_string += getCurrentDateTime() + ";";

    size_t pos = -1;
    for (int i = 0; i < std::atoi(devices_ips[dev_i + 1]); i++) {
        pos = raw_response.find("$", pos + 1);
        pos = raw_response.find("$", pos + 1);

        std::string sensor = raw_response.substr(pos + 1, raw_response.find(";", pos) - pos - 1);
        save_string += sensor + ";";
    }
    return save_string;
}

bool checked = false;
int check_min = 0;

int main() {
    int last_checked_minute = -1;

    while (true) {
        auto now = std::chrono::system_clock::now();
        std::time_t now_c = std::chrono::system_clock::to_time_t(now);
        std::tm* ltm = std::localtime(&now_c);

        std::cout << "\nChecking now: " << std::put_time(ltm, "%d/%m/%Y %H:%M:%S") << std::endl;

        int current_minute = ltm->tm_min;

        if (current_minute % minute_interval != 0 || current_minute == last_checked_minute) {
            now = std::chrono::system_clock::now();
            auto next_minute = std::chrono::time_point_cast<std::chrono::minutes>(now) + std::chrono::minutes(1);
            std::this_thread::sleep_until(next_minute);
            continue;
        }

        last_checked_minute = current_minute;

        for (int dev_i = 0; dev_i < num_devices; dev_i++) {
            const char* sensor_device_ip = devices_ips[dev_i];
            std::cout << "Processing device: " << sensor_device_ip << " i: " << dev_i << std::endl;

            std::string response = getResponse(sensor_device_ip);
	    std::cout << "response: " << response << std::endl;

            if (response == "") {
                std::cerr << "No response received from " << sensor_device_ip << ".\n";
                continue;
            }

            std::string save_string = getDataString(response, dev_i);
            std::cout << save_string << std::endl;
            if (save_string.find("500 Internal server error") != std::string::npos || save_string.find("404 Not Found") != std::string::npos)
            {
                std::cout << "Ignoring...\n";
                continue;
            }

            // Append to file
            std::ofstream outFile("devs/" + std::string(sensor_device_ip) + ".txt", std::ios::app);
	    std::cout << "attempting write to devs/" << std::string(sensor_device_ip) << ".txt..." << std::endl;
            if (outFile.is_open()) {
		std::cout << "writing to file devs/" << std::string(sensor_device_ip) << ".txt" << std::endl;
                outFile << save_string << std::endl;
                outFile.close();
            } else {
                std::cerr << "Failed to open file for " << sensor_device_ip << ".\n";
            }
        }
    }

    return 0;
}

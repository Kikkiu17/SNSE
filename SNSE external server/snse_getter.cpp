#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cstring>
#include <unistd.h>
#include <arpa/inet.h>
#include <ctime>
#include <iomanip>
#include <thread>

const int minute_interval = 1;
const int server_port = 34677;
const char* request = "GET ?features";
const int buf_size = 4096;

struct Device {
    std::string ip;
    int sensor_count;
};

std::vector<Device> loadDevices(const std::string& filename) {
    std::vector<Device> devices;
    std::ifstream infile(filename);
    std::string ip;
    int count;

    while (infile >> ip >> count) {
        devices.push_back({ip, count});
    }

    return devices;
}

std::string getCurrentDateTime() {
    std::time_t now = std::time(nullptr);
    std::tm* localTime = std::localtime(&now);
    std::ostringstream oss;
    oss << std::put_time(localTime, "%d/%m/%Y;%H:%M");
    return oss.str();
}

std::string getResponse(const std::string& dev_ip) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "Error creating socket\n";
        return "";
    }

    sockaddr_in server_addr{};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(server_port);
    if (inet_pton(AF_INET, dev_ip.c_str(), &server_addr.sin_addr) <= 0) {
        std::cerr << "Invalid address or address not supported\n";
        close(sock);
        return "";
    }

    if (connect(sock, (sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        std::cerr << "Connection failed\n";
        close(sock);
        return "";
    }

    if (send(sock, request, strlen(request), 0) < 0) {
        std::cerr << "Send failed\n";
        close(sock);
        return "";
    }

    char buffer[buf_size];
    ssize_t bytes_received = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (bytes_received < 0) {
        std::cerr << "Receive failed\n";
        close(sock);
        return "";
    }

    buffer[bytes_received] = '\0';
    std::string response(buffer);
    close(sock);
    return response;
}

std::string getDataString(const std::string& raw_response, int sensor_count) {
    std::string save_string = getCurrentDateTime() + ";";
    size_t pos = -1;

    for (int i = 0; i < sensor_count; ++i) {
        pos = raw_response.find("$", pos + 1);
        pos = raw_response.find("$", pos + 1);
        std::string sensor = raw_response.substr(pos + 1, raw_response.find(";", pos) - pos - 1);
        save_string += sensor + ";";
    }

    return save_string;
}

int main() {
    int last_checked_minute = -1;

    while (true) {
        auto now = std::chrono::system_clock::now();
        std::time_t now_c = std::chrono::system_clock::to_time_t(now);
        std::tm* ltm = std::localtime(&now_c);

        std::cout << "\nChecking now: " << std::put_time(ltm, "%d/%m/%Y %H:%M:%S") << std::endl;

        int current_minute = ltm->tm_min;

        if (current_minute % minute_interval != 0 || current_minute == last_checked_minute) {
            auto next_minute = std::chrono::time_point_cast<std::chrono::minutes>(now) + std::chrono::minutes(1);
            std::this_thread::sleep_until(next_minute);
            continue;
        }

        last_checked_minute = current_minute;

        // reload device list at every update
        std::vector<Device> devices = loadDevices("devs_list.txt");

        for (size_t dev_i = 0; dev_i < devices.size(); ++dev_i) {
            const std::string& sensor_device_ip = devices[dev_i].ip;
            int sensor_count = devices[dev_i].sensor_count;

            std::cout << "Processing device: " << sensor_device_ip << " i: " << dev_i << std::endl;

            std::string response = getResponse(sensor_device_ip);
            std::cout << "response: " << response << std::endl;

            if (response.empty() || response == "") {
                std::cerr << "No response received from " << sensor_device_ip << ".\n";
                continue;
            }

            std::string save_string = getDataString(response, sensor_count);
            std::cout << save_string << std::endl;

            if (save_string.find("500 Internal server error") != std::string::npos ||
                save_string.find("404 Not Found") != std::string::npos) {
                std::cout << "Ignoring...\n";
                continue;
            }

            std::ofstream outFile("devs/" + sensor_device_ip + ".txt", std::ios::app);
            std::cout << "attempting write to devs/" << sensor_device_ip << ".txt..." << std::endl;

            if (outFile.is_open()) {
                std::cout << "writing to file devs/" << sensor_device_ip << ".txt" << std::endl;
                outFile << save_string << std::endl;
                outFile.close();
            } else {
                std::cerr << "Failed to open file for " << sensor_device_ip << ".\n";
            }
        }
    }

    return 0;
}

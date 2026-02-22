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

const int minute_interval = 5;
const int server_port = 34677;
const char* request = "GET ?features\r\n";
const int buf_size = 4096;

// Loads a plain list of IPs, one per line:
//   xxx.xxx.xxx.xxx
//   yyy.yyy.yyy.yyy
std::vector<std::string> loadDevices(const std::string& filename) {
    std::vector<std::string> ips;
    std::ifstream infile(filename);
    std::string ip;

    while (std::getline(infile, ip)) {
        // strip trailing whitespace/carriage return
        while (!ip.empty() && (ip.back() == '\r' || ip.back() == ' '))
            ip.pop_back();
        if (!ip.empty())
            ips.push_back(ip);
    }

    return ips;
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

// Counts how many sensors are marked with $graph_ in the response.
// The response format is:
//   200 OK\nsensor1$label$value$graph_W_Wh;sensor2$label$value;...
int countGraphedSensors(const std::string& raw_response) {
    int count = 0;
    size_t pos = 0;
    while ((pos = raw_response.find("$graph_", pos)) != std::string::npos) {
        count++;
        pos++;
    }
    return count;
}

std::string getDataString(const std::string& raw_response) {
    std::string save_string = getCurrentDateTime() + ";";
    size_t pos = -1;

    while (true) {
        // find next sensor block: skip sensor name ($), skip label ($)
        size_t name_dollar = raw_response.find("$", pos + 1);
        if (name_dollar == std::string::npos) break;

        size_t label_dollar = raw_response.find("$", name_dollar + 1);
        if (label_dollar == std::string::npos) break;

        // value runs from after label_dollar to the next $ or ;
        size_t next_dollar = raw_response.find("$", label_dollar + 1);
        size_t next_semi   = raw_response.find(";", label_dollar + 1);

        if (next_semi == std::string::npos) break;

        if (next_dollar != std::string::npos && next_dollar < next_semi) {
            // graphed sensor: value$graph_W_Wh;
            std::string value      = raw_response.substr(label_dollar + 1, next_dollar - label_dollar - 1);
            std::string graph_label = raw_response.substr(next_dollar + 1, next_semi - next_dollar - 1);

            // strip unit from value if present (e.g. "81.75 W" -> "81.75")
            std::string numeric = value.substr(0, value.find(" "));
            save_string += numeric + ":" + graph_label + ";";
            pos = next_semi;
        } else {
            // non-graphed sensor: skip entirely
            pos = next_semi;
        }

        // stop if we've passed the end of the sensor list
        if (pos == std::string::npos || pos >= raw_response.size()) break;
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
        std::vector<std::string> ips = loadDevices("devs_list.txt");

        for (size_t dev_i = 0; dev_i < ips.size(); ++dev_i) {
            const std::string& sensor_device_ip = ips[dev_i];

            std::cout << "Processing device: " << sensor_device_ip << " i: " << dev_i << std::endl;

            std::string response = getResponse(sensor_device_ip);
            std::cout << "response: " << response << std::endl;

            if (response.empty()) {
                std::cerr << "No response received from " << sensor_device_ip << ".\n";
                continue;
            }

            if (response.find("500 Internal server error") != std::string::npos ||
                response.find("404 Not Found") != std::string::npos) {
                std::cout << "Ignoring error response from " << sensor_device_ip << "\n";
                continue;
            }

            // skip devices with no graphed sensors
            if (countGraphedSensors(response) == 0) {
                std::cout << "No graphed sensors for " << sensor_device_ip << ", skipping.\n";
                continue;
            }

            std::string save_string = getDataString(response);
            std::cout << save_string << std::endl;

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
#include <iostream>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <vector>

#include <ctime>
#include <sstream>
#include <fstream>
#include <iomanip>

#include <algorithm>

void sendResponse(int client_fd, const std::string& code, const std::string& response)
{
    std::string fullResponse = code + "\n" + response + "\r\n";
    send(client_fd, fullResponse.c_str(), fullResponse.length(), 0);
}

std::string getCurrentDateTime()
{
    std::time_t now = std::time(nullptr);
    std::tm* localTime = std::localtime(&now);

    std::ostringstream oss;
    oss << std::put_time(localTime, "%d/%m/%Y;%H:%M");
    return oss.str();
}

class Pair
{
public:
    Pair(std::string _key, std::string _value)
    {
        key = _key;
        value = _value;
    }
    std::string key;
    std::string value;
};

std::vector<Pair> pairs;

std::string getUnit(std::string line, int separation_index)
{
    int pos = -1;
    int i = 0;
    while (true)
    {
        int unit_start = line.find(" ", pos + 1);
        int unit_end = line.find(";", pos + 1);

        std::string unit = line.substr(unit_start + 1, unit_end - 1 - unit_start);

        if (i == separation_index)
            return unit;

        i++;

        if ((pos = line.find(";", pos + 1)) == std::string::npos)
            return "";
    }
}

std::string getLineSeparatedValue(std::string line, int index)
{
    int pos = -1;
    int i = 0;
    while (true)
    {
        int value_start = pos + 1;
        int value_end = line.find(" ", pos + 1);
        if (value_end == std::string::npos)
            value_end = line.find(";", pos + 1);
        if (value_end == std::string::npos) continue;

        std::string value = line.substr(value_start, value_end - value_start);

        if (i == index)
            return value;

        i++;

        if ((pos = line.find(";", pos + 1)) == std::string::npos)
            return "";
    }
}

void getDays(int client_fd, std::string ip)
{
    std::ifstream file("devs/" + ip + ".txt");

    if (!file.is_open())
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
        return;
    }
    
    std::vector<std::string> days;
    std::string line;
    std::string date = pairs[1].value; // Expected format: dd/mm/yyyy
    
    while (std::getline(file, line))
    {
        std::string line_date = line.substr(0, line.find(";"));
        if (std::find(days.begin(), days.end(), line_date) == days.end())
        days.push_back(line_date);
    }
    
    file.close();
    
    if (days.empty())
        sendResponse(client_fd, "404 Not Found", "No data found\n");
    else
    {
        std::string response;
        for (size_t i = 0; i < days.size(); ++i)
        {
            response += days[i];
            if (i != days.size() - 1)
            response += "\n";
        }
        
        sendResponse(client_fd, "200 OK", response);
    }
}

void getDataDay(int client_fd, std::string ip, std::string day)
{
    std::ifstream file("devs/" + ip + ".txt");
    
    if (!file.is_open())
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
        return;
    }

    std::vector<std::string> requested_data;

    std::string line;
    std::string date = day; // Expected format: dd/mm/yyyy

    while (std::getline(file, line))
    {
        if (line.find(date) != std::string::npos)
            requested_data.push_back(line);
    }

    file.close();

    if (requested_data.empty())
        sendResponse(client_fd, "404 Not Found", "No data found\n");
    else
    {
        std::string response;
        for (size_t i = 0; i < requested_data.size(); ++i)
        {
            response += requested_data[i];
            if (i != requested_data.size() - 1)
                response += "\n";
        }

        sendResponse(client_fd, "200 OK", response);
    }
}

std::string getMonths(int client_fd, std::string ip, bool noresponse = false)
{
    std::ifstream file("devs/" + ip + ".txt");
    
    if (!file.is_open())
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
        return "";
    }

    std::vector<std::string> months;
    std::string line;
    std::string date = pairs[1].value; // Expected format: dd/mm/yyyy

    while (std::getline(file, line))
    {
        std::string line_date = line.substr(0, line.find(";"));
        std::string line_month = line_date.substr(3, 7);

        if (std::find(months.begin(), months.end(), line_month) == months.end())
            months.push_back(line_month);
    }

    file.close();

    if (months.empty())
    {
        if (!noresponse)
            sendResponse(client_fd, "404 Not Found", "No data found\n");
        return "";
    }
    else
    {
        std::string response;
        for (size_t i = 0; i < months.size(); ++i)
        {
            response += months[i];
            if (i != months.size() - 1)
                response += "\n";
        }

        if (!noresponse)
            sendResponse(client_fd, "200 OK", response);
        return response;
    }
}

void getAverageDataMonth(int client_fd, std::string ip, std::string month)
{
    // average the data of each day
    std::ifstream file("devs/" + ip + ".txt");
    
    if (!file.is_open())
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
        return;
    }

    std::vector<std::string> days;
    std::string line;
    std::vector<std::string> units;

    int sensor_number = 0;
    std::vector<std::vector<float>> days_averaged_sensors;

    bool first = true;
    std::string current_day = "";
    int day_i = -1;

    // average data
    while (std::getline(file, line))
    {
        if (first)
        {
            first = false;
            // dd/mm/yyyy;hh:mm;s1;s2;s3...
            int pos = 16;
            while (true)
            {
                if ((pos = line.find(";", pos + 1)) != std::string::npos)
                    sensor_number++;
                else break;
            }
            if (sensor_number == 0) return;
            units.resize(sensor_number);
            for (int i = 0; i < sensor_number; i++)
            {
                units[i] = getUnit(line, i + 2);
            }
        }

        std::string linedate = line.substr(0, line.find(";"));
        std::string linemonth = linedate.substr(3, 2);

        if (linemonth == month)
        {
            if (linedate != current_day)
            {
                current_day = linedate;
                days.push_back(linedate);
                days_averaged_sensors.push_back(std::vector<float>(sensor_number));
                day_i++;
            }
            if (linedate == current_day)
            {
                std::string sensor_data = line.erase(0, 17);
                for (int sens_i = 0; sens_i < sensor_number; sens_i++)
                {
                    float parsed_sensor_data = std::stof(sensor_data.substr(0, sensor_data.find(";")));
                    if (days_averaged_sensors[day_i][sens_i] == 0)
                        days_averaged_sensors[day_i][sens_i] = parsed_sensor_data;
                    else
                        days_averaged_sensors[day_i][sens_i] = (days_averaged_sensors[0][sens_i] + parsed_sensor_data) / 2;
                }
            }
        }
    }
    
    file.close();

    std::string prepared_data = "";
    // organize data to be sent
    for (int day_i = 0; day_i < days.size(); day_i++)
    {
        std::string data = "";
        std::string day = days[day_i];
        std::vector<float> sensors = days_averaged_sensors[day_i];

        data += day + ";";
        for (int sens_i = 0; sens_i < sensors.size(); sens_i++)
        {
            data += std::to_string(sensors[sens_i]) + " " + units[sens_i];
            if (sens_i != sensors.size() - 1)
                data += ";";
        }
        data += "\n";


        prepared_data += data;
    }

    if (prepared_data == "")
        sendResponse(client_fd, "404 Not Found", "No data found\n");
    else
        sendResponse(client_fd, "200 OK", prepared_data);
}

int count(std::string line, std::string to_count, int offset)
{
    int counter = 0;
    int pos = offset;
    
    while (true)
    {
        if ((pos = line.find(to_count, pos + 1)) != std::string::npos)
            counter++;
        else break;
    }
    return counter;
}

std::string getTotalDataMonth(int client_fd, std::string ip, std::string month, bool noresponse = false)
{
    // get total of each day
    std::ifstream file("devs/" + ip + ".txt");
    
    if (!file.is_open())
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
        return "";
    }

    std::vector<std::string> days;
    std::string line;

    int sensor_number = 0;
    std::vector<std::vector<float>> days_total_sensors;
    std::vector<std::string> units;
    
    int day_i = -1;
    int line_i = 0;

    float time_interval_calibration_value = 1.0f;   // time_interval (minutes) / 60
    std::string first_line = "";

    bool first = true;
    std::string current_day = "";

    while (std::getline(file, line))
    {
        if (first_line == "")
            first_line = line;

        if (first)
        {
            first = false;
            // dd/mm/yyyy;hh:mm;s1;s2;s3...
            sensor_number = count(line, ";", 16);
            if (sensor_number == 0) return "";

            units.resize(sensor_number);
            for (int i = 0; i < sensor_number; i++)
            {
                units[i] = getUnit(line, i + 2);
            }
        }

        if (line_i == 1)
        {
            int this_line_minutes = std::stoi(line.substr(15, 2));
            int first_line_minutes = std::stoi(first_line.substr(15, 2));
            int time_interval = abs(this_line_minutes - first_line_minutes);
            time_interval_calibration_value = time_interval / 60.0f;
        }

        std::string linedate = line.substr(0, line.find(";"));
        std::string linemonth = linedate.substr(3, 7);

        if (linemonth == month)
        {
            if (linedate != current_day)
            {
                current_day = linedate;
                days.push_back(linedate);
                days_total_sensors.push_back(std::vector<float>(sensor_number));
                day_i++;
            }
            if (linedate == current_day)
            {
                std::string sensor_data = line.erase(0, 17);
                for (int sens_i = 0; sens_i < sensor_number; sens_i++)
                {
                    std::string value = getLineSeparatedValue(sensor_data, sens_i);
                    float parsed_sensor_data = std::stof(value.substr(0, value.find(";")));
                    days_total_sensors[day_i][sens_i] += parsed_sensor_data * time_interval_calibration_value;
                }
            }
        }

        line_i++;
    }
    
    file.close();

    std::string prepared_data = "";
    // organize data to be sent
    for (int day_i = 0; day_i < days.size(); day_i++)
    {
        std::string data = "";
        std::string day = days[day_i];
        std::vector<float> sensors = days_total_sensors[day_i];

        data += day + ";";
        for (int sens_i = 0; sens_i < sensors.size(); sens_i++)
        {
            data += std::to_string(sensors[sens_i]) + " " + units[sens_i];
            if (sens_i != sensors.size() - 1)
                data += ";";
        }
        data += "\n";


        prepared_data += data;
    }

    if (prepared_data == "")
    {
        if (!noresponse)
            sendResponse(client_fd, "404 Not Found", "No data found\n");
        return "";
    }
    else
    {
        if (!noresponse)
            sendResponse(client_fd, "200 OK", prepared_data);
        return prepared_data;
    }
}

void getYears(int client_fd, std::string ip)
{
    std::ifstream file("devs/" + ip + ".txt");
    
    if (!file.is_open())
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
        return;
    }

    std::vector<std::string> years;
    std::string line;
    std::string date = pairs[1].value; // Expected format: dd/mm/yyyy

    while (std::getline(file, line))
    {
        std::string line_date = line.substr(0, line.find(";"));
        std::string line_year = line_date.substr(6, 4);

        if (std::find(years.begin(), years.end(), line_year) == years.end())
            years.push_back(line_year);
    }

    file.close();

    if (years.empty())
        sendResponse(client_fd, "404 Not Found", "No data found\n");
    else
    {
        std::string response;
        for (size_t i = 0; i < years.size(); ++i)
        {
            response += years[i];
            if (i != years.size() - 1)
                response += "\n";
        }

        sendResponse(client_fd, "200 OK", response);
    }
}

void getDataYear(int client_fd, std::string ip, std::string year)
{
    int month_pos = -1;
    std::string months = getMonths(client_fd, ip, true);
    if (months == "") return;

    std::vector<std::string> months_vec;
    std::vector<std::vector<float>> months_total_sensors;
    std::vector<std::string> units;
    bool first = true;
    int month_i = 0;

    do {
        int day_pos = 0;
        first = true;

        std::string this_month = months.substr(month_pos + 1, 7);
        std::cout << this_month << std::endl;

        std::string this_year = this_month.substr(3, 4);
        if (this_year != year) continue;

        std::string month_data = getTotalDataMonth(client_fd, ip, this_month, true);
        months_vec.push_back(this_month);


        while ((day_pos = month_data.find("\n", day_pos + 1)) != std::string::npos)
        {
            std::string day_data = month_data.substr(0, day_pos);
            int sensors_number = count(day_data, ";", 0);

            if (first)
            {
                first = false;
                months_total_sensors.push_back(std::vector<float>(sensors_number));
                units.resize(sensors_number);
                for (int i = 0; i < sensors_number; i++)
                {
                    units[i] = getUnit(day_data, i + 1);
                }
            }

            day_data += ";";
            int day_sensor_pos = 0;

            day_data = day_data.erase(0, day_data.find(";") + 1);

            for (int sens_i = 0; sens_i < sensors_number; sens_i++)
            {
                day_sensor_pos = day_data.find(";", 0);
                std::string day_sensor = day_data.substr(0, day_sensor_pos);
                months_total_sensors[month_i][sens_i] += std::stof(day_sensor);

                day_data.erase(0, day_sensor_pos + 1);
            }

            month_data = month_data.erase(0, day_pos + 1);
            day_pos = 0;
        }
        
        month_i++;
    } while ((month_pos = months.find("\n", month_pos + 1)) != std::string::npos);

    std::string prepared_data = "";
    // organize data to be sent
    for (int month_i = 0; month_i < months_vec.size(); month_i++)
    {
        std::string data = "";
        std::string month = months_vec[month_i];
        std::vector<float> sensors = months_total_sensors[month_i];

        data += month + ";";
        for (int sens_i = 0; sens_i < sensors.size(); sens_i++)
        {
            data += std::to_string(sensors[sens_i]) + " " + units[sens_i];
            if (sens_i != sensors.size() - 1)
                data += ";";
        }
        data += "\n";

        prepared_data += data;
    }

    if (prepared_data == "")
    {
        sendResponse(client_fd, "404 Not Found", "No data found\n");
    }
    else
    {
        sendResponse(client_fd, "200 OK", prepared_data);
    }
}

void handleGET(int client_fd, std::string req)
{
    req = req.erase(0, req.find(" ") + 2); // Remove "GET ?"

    pairs.clear();

    int key_value_pairs = 0;

    if (req.find("&") == std::string::npos)
        key_value_pairs = 1;
    else
    {
        size_t pos = 0;
        pos = req.find("&", pos);

        if (pos != std::string::npos) key_value_pairs = 1; // Count first pair

        while (pos != std::string::npos)
        {
            key_value_pairs++;
            pos = req.find("&", pos + 1);
        }
    }

    req.append("&"); // simplify parsing

    // remove trailing \r\n, not needed
    std::size_t pos = req.find("\r\n");
    if (pos != std::string::npos)
        req.replace(pos, 2, "");

    for (int i = 0; i < key_value_pairs; i++)
    {
        std::string pair = req.substr(0, req.find("&"));
        req = req.erase(0, req.find("&") + 1);

        std::string key = pair.substr(0, pair.find("="));
        std::string value = pair.substr(pair.find("=") + 1);

        pairs.push_back(Pair(key, value));
    }

    if (pairs[0].key != "dev")
    {
        const char* response = "Request must start with dev=<ip>!\n";
        send(client_fd, response, strlen(response), 0);
        return;
    }
    std::string ip = pairs[0].value;

    if (pairs[1].key == "time")
    {
        if (pairs[1].value == "days")
        {
            if (pairs.size() <= 2)
            {
                getDays(client_fd, ip);
            }
            else if (pairs[2].key == "data")
                getDataDay(client_fd, ip, pairs[2].value);
            else
                sendResponse(client_fd, "400 Invalid request", "Unknown command");
        }
        else if (pairs[1].value == "months")
        {
            if (pairs.size() <= 2)
                getMonths(client_fd, ip);
            else if (pairs[2].key == "data")
                getTotalDataMonth(client_fd, ip, pairs[2].value);
            else
                sendResponse(client_fd, "400 Invalid request", "Unknown command");
        }
        else if (pairs[1].value == "years")
        {
            if (pairs.size() <= 2)
                getYears(client_fd, ip);
            else if (pairs[2].key == "data")
                getDataYear(client_fd, ip, pairs[2].value);
            else
                sendResponse(client_fd, "400 Invalid request", "Unknown command");
        }
    }
}

void handlePOST(int client_fd, std::string req)
{
    const char* response = "this is a post req\n";
    send(client_fd, response, strlen(response), 0);
}

int main()
{
    const int port = 34678;
    const int bufferSize = 1024;
    char buffer[bufferSize];

    // Create socket
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0)
    {
        std::cerr << "Socket creation failed\n";
        return 1;
    }

    // Bind address
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    int opt = 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0)
    {
        std::cerr << "setsockopt failed\n";
        close(server_fd);
        return 1;
    }

    if (bind(server_fd, (sockaddr*)&address, sizeof(address)) < 0)
    {
        std::cerr << "Bind failed\n";
        close(server_fd);
        return 1;
    }

    // Listen for connections
    if (listen(server_fd, 3) < 0)
    {
        std::cerr << "Listen failed\n";
        close(server_fd);
        return 1;
    }

    std::cout << "Server listening on port " << port << "...\n";

    while (true)
    {
        sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (sockaddr*)&client_addr, &client_len);
        if (client_fd < 0)
        {
            std::cerr << "Accept failed\n";
            continue;
        }

        while (true)
        {
            // Receive request
            ssize_t bytes_received = recv(client_fd, buffer, bufferSize - 1, 0);
            if (bytes_received <= 0) {
                std::cout << "Client disconnected or error occurred.\n";
                break;
            }

            buffer[bytes_received] = '\0';
            std::string request(buffer);
            std::cout << "Received: " << request << std::endl;

            std::string response_type = request.substr(0, request.find(" "));

            // Respond to specific request
            if (response_type == "GET")
            {
                handleGET(client_fd, request);
            }
            else if (response_type == "POST")
            {
                handlePOST(client_fd, request);
            }
            else
            {
                const char* response = "Only POST and GET requests are supported\n";
                send(client_fd, response, strlen(response), 0);
            }
        }
        close(client_fd); // TIENI CONNESSIONE APERTA

    }

    close(server_fd); // Close server socket
    return 0;
}

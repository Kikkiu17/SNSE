import 'package:easy_localization/easy_localization.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:developer' as debug;

import '../tiles/tiles.dart';
import '../pages/device.dart';
import 'pages/settings.dart';

List<dynamic> features = List.empty(growable: true);

// these are the IDs of the external features - add new ones as needed
const int chart = 1;

const List<String> remoteTimeframes = [
  "days",
  "months",
  "years"
];

List<String> translatedTimeframes = [
  "device.day".tr(),
  "device.month".tr(),
  "device.year".tr()
];

List<String> translatedMonths = [
  "device.jan".tr(),
  "device.feb".tr(),
  "device.mar".tr(),
  "device.apr".tr(),
  "device.may".tr(),
  "device.jun".tr(),
  "device.jul".tr(),
  "device.aug".tr(),
  "device.sep".tr(),
  "device.oct".tr(),
  "device.nov".tr(),
  "device.dec".tr(),
];

class ListValue {
  ListValue(this.time, this.data);
  final String time;
  final double? data;
}

// Holds all data points for a single graphed sensor series
class SeriesData {
  SeriesData(this.name);
  final String name;
  List<ListValue> data = List.empty(growable: true);
}

class Chart {
  String rawSelectedValue = "";
  String selectedValue = "";
  String selectedTimeframeTranslated = translatedTimeframes[0];
  String selectedTimeframe = remoteTimeframes[0];
  bool selectedTimeFrameChanged = false;
  List<String> rawOptions = List.empty(growable: true);
  List<String> translatedOptions = List.empty(growable: true);

  // Each entry is one graphed sensor series
  List<SeriesData> series = List.empty(growable: true);

  // Parses a single data line's sensor fields and returns graphed series by index.
  // Fields with :graph suffix are included; others are skipped.
  // sensorFields: the semicolon-split parts starting from the first sensor column.
  // If series list is empty (first line), initializes them from the sensor labels.
  // timeframe should be "days", "months", or "years" - used to pick the correct series label
  // Label format in data: value:graph_DayLabel_MonthYearLabel (e.g. 123:graph_W_Wh)
  // If only one label is provided (e.g. :graph_Wh), it is used for all timeframes.
  void _parseSensorFields(String time, List<String> sensorFields, String timeframe) {
    bool initializingSeries = series.isEmpty;
    int seriesIndex = 0;

    for (String field in sensorFields) {
      if (field.isEmpty) continue;

      bool isGraphed = field.contains(":graph_");
      String cleanField = field;
      String seriesLabel = "Sensor ${seriesIndex + 1}"; // fallback

      if (isGraphed) {
        int markerPos = field.indexOf(":graph_");
        String labelPart = field.substring(markerPos + 7); // e.g. "W_Wh"
        cleanField = field.substring(0, markerPos);

        // Split on first underscore only, so labels themselves can contain underscores
        int separatorPos = labelPart.indexOf("_");

        // If there is no second label (e.g. "graph_W" with no underscore),
        // this sensor is only meaningful for the days view — skip it for months/years.
        if (separatorPos == -1 && timeframe != "days") continue;

        String dayLabel   = separatorPos != -1 ? labelPart.substring(0, separatorPos) : labelPart;
        String otherLabel = separatorPos != -1 ? labelPart.substring(separatorPos + 1) : labelPart;

        if (timeframe == "days") {
          seriesLabel = dayLabel;   // e.g. "Potenza (W)"
        } else {
          seriesLabel = otherLabel; // e.g. "Energia (Wh)"
        }
      }

      // Remove unit if present (e.g. "123 °C" -> "123")
      List<String> valueSplit = cleanField.split(" ");
      String rawValue = valueSplit[0];

      if (!isGraphed) continue;

      if (initializingSeries) {
        series.add(SeriesData(seriesLabel));
      }

      if (seriesIndex < series.length) {
        series[seriesIndex].data.add(ListValue(time, double.tryParse(rawValue) ?? 0.0));
      }

      seriesIndex++;
    }
  }

  // EXPECTED DATA SHOULD BE IN THIS FORM: yyyy;sens1:graph_X_Xh;sens2:graph_Y_Yh;...
  final int dayTimeIndex = 1;
  final int dayFirstSensorIndex = 2;
  Future<void> parseChartDaysData(String rawResponse) async {
    series = List.empty(growable: true);
    List<String> rawChartData = rawResponse.split("\n");
    rawChartData.removeAt(0); // remove status code line

    if (rawChartData.isNotEmpty) {
      for (String line in rawChartData) {
        List<String> parts = line.split(";");
        if (parts.length > dayFirstSensorIndex) {
          try {
            String time = parts[dayTimeIndex];
            List<String> sensorFields = parts.sublist(dayFirstSensorIndex);
            _parseSensorFields(time, sensorFields, "days");
          } catch (e) {
            debug.log("Error parsing line: $line, error: $e");
          }
        }
      }
    }
  }

  // EXPECTED DATA SHOULD BE IN THIS FORM: yyyy;sens1:graph_X_Xh;sens2:graph_Y_Yh;...
  final int monthDateIndex = 0;
  final int monthFirstSensorIndex = 1;
  Future<void> parseChartMonthsData(String rawResponse) async {
    series = List.empty(growable: true);
    List<String> rawChartData = rawResponse.split("\n");
    rawChartData.removeAt(0);

    if (rawChartData.isNotEmpty) {
      for (String line in rawChartData) {
        List<String> parts = line.split(";");
        if (parts.length > monthFirstSensorIndex) {
          try {
            String date = parts[monthDateIndex];
            List<String> sensorFields = parts.sublist(monthFirstSensorIndex);
            _parseSensorFields(date, sensorFields, "months");
          } catch (e) {
            debug.log("Error parsing line: $line, error: $e");
          }
        }
      }
    }
  }

  // EXPECTED DATA SHOULD BE IN THIS FORM: yyyy;sens1:graph_X_Xh;sens2:graph_Y_Yh;...
  final int yearDateIndex = 0;
  final int yearFirstSensorIndex = 1;
  Future<void> parseChartYearsData(String rawResponse) async {
    series = List.empty(growable: true);
    List<String> rawChartData = rawResponse.split("\n");
    rawChartData.removeAt(0);

    if (rawChartData.isNotEmpty) {
      for (String line in rawChartData) {
        List<String> parts = line.split(";");
        if (parts.length > yearFirstSensorIndex) {
          try {
            String date = parts[yearDateIndex];
            List<String> sensorFields = parts.sublist(yearFirstSensorIndex);
            _parseSensorFields(date, sensorFields, "years");
          } catch (e) {
            debug.log("Error parsing line: $line, error: $e");
          }
        }
      }
    }
  }
}

Future<List<Widget>> getChart(String ip, index, BuildContext context, ValueNotifier addListener) async {
  TcpClient extServer = TcpClient();
  extServer.customTimeout = extServerTimeout;
  Chart chart = features[index];

  bool connected = await extServer.connect(savedSettings.getExtServerIP(), extServerPort, null);
  if (!connected) {
    return [grayTextCenteredTile("device.external_feature_no_connection".tr(args: [savedSettings.getExtServerIP()]))];
  }

  String response = "";

  if (chart.selectedValue == "" || chart.selectedTimeFrameChanged) {
    chart.selectedTimeFrameChanged = false;
    // populate fields for the first time
    response = await extServer.sendData("GET ?dev=$ip&time=${chart.selectedTimeframe}");
    chart.translatedOptions = response.split("\n");
    chart.translatedOptions.removeAt(0);  // removes status code
    chart.selectedValue = response.split("\n")[response.split("\n").length - 1]; // initial (latest) date

    chart.rawOptions = response.split("\n");
    chart.rawOptions.removeAt(0); // removes status code
    chart.rawSelectedValue = chart.rawOptions[chart.translatedOptions.indexOf(chart.selectedValue)];
  }

  // translate options (like 09/2025 to September)
  if (chart.selectedTimeframe == "months" && !translatedMonths.contains(chart.selectedValue.split(" ")[0])) {
    chart.selectedValue = "${translatedMonths[int.parse(chart.selectedValue.split("/")[0]) - 1]} ${chart.selectedValue.split("/")[1]}";
    chart.translatedOptions = chart.translatedOptions.map((option) {
      int monthIndex = int.parse(option.split("/")[0]);
      String year = option.split("/")[1];
      return "${translatedMonths[monthIndex - 1]} $year";
    }).toList();
  }

  response = await extServer.sendData("GET ?dev=$ip&time=${chart.selectedTimeframe}&data=${chart.rawSelectedValue}");
  extServer.disconnect();

  // handle different timeframes
  if (chart.selectedTimeframe == "days") {
    await chart.parseChartDaysData(response);
  } else if (chart.selectedTimeframe == "months") {
    await chart.parseChartMonthsData(response);
  } else if (chart.selectedTimeframe == "years") {
    await chart.parseChartYearsData(response);
  }

  List<Widget> externalWidgets = List.empty(growable: true);

  if (!context.mounted) return List.empty(growable: false);

  // Build one LineSeries per graphed sensor
  List<CartesianSeries<ListValue, String>> chartSeries = chart.series.map((s) {
    return LineSeries<ListValue, String>(
      dataSource: s.data,
      xValueMapper: (ListValue listValue, _) => listValue.time,
      yValueMapper: (ListValue listValue, _) => listValue.data,
      name: s.name,
    );
  }).toList();

  externalWidgets.add(
    SfCartesianChart(
      zoomPanBehavior: ZoomPanBehavior(
        enableMouseWheelZooming: true,
        zoomMode: ZoomMode.x,
        enablePanning: true,
        enableSelectionZooming: true,
        selectionRectBorderColor: Theme.of(context).primaryColor,
        selectionRectBorderWidth: 1,
        selectionRectColor: Colors.grey,
        enablePinching: true
      ),
      primaryXAxis: const CategoryAxis(
        labelRotation: -45,
      ),
      title: ChartTitle(text: chart.selectedValue),
      legend: const Legend(isVisible: true, position: LegendPosition.top),
      tooltipBehavior: TooltipBehavior(enable: true),
      series: chartSeries,
    )
  );

  // VALUE DROPDOWN MENU (like 07/08/2025, September or 2025)
  externalWidgets.add(
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 15),
          child: Text("device.time_interval".tr()),
        ),
        DropdownButton<String>(
          menuMaxHeight: 300,
          value: chart.selectedValue,
          items: chart.translatedOptions
              .map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (String? newValue) async {
            chart.selectedValue = newValue!;
            chart.rawSelectedValue = chart.rawOptions[chart.translatedOptions.indexOf(chart.selectedValue)];
            addListener.value = !addListener.value;
          },
        ),
      ],
    )
  );

  // TIMEFRAME DROPDOWN
  externalWidgets.add(
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 15),
          child: Text("device.value".tr()),
        ),
        DropdownButton<String>(
          value: chart.selectedTimeframeTranslated,
          items: translatedTimeframes
              .map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (String? newValue) async {
            chart.selectedTimeframeTranslated = newValue!;
            chart.selectedTimeframe = remoteTimeframes[translatedTimeframes.indexOf(newValue)];
            chart.selectedTimeFrameChanged = true;
            addListener.value = !addListener.value;
          },
        ),
      ],
    )
  );

  externalWidgets.add(
    ListTile(
      title: ElevatedButton(
        child: Text("device.update_graph_text".tr()),
        onPressed: () {
          addListener.value = !addListener.value;
        }
      )
    )
  );

  return externalWidgets;
}

Future<List<Widget>> getExternalFeature(String ip, int id, int index, BuildContext context, ValueNotifier<bool> addListener) async {
  List<Widget> featuresToReturn = List.empty(growable: true);
  if (id < 0) return [Text("error".toUpperCase())];
  if (id == chart) {
    featuresToReturn.addAll(await getChart(ip, index, context, addListener));
  }

  return featuresToReturn;
}

void createExternalFeature(int id)
{
  if (id == chart) {
    features.add(Chart());
  }
}
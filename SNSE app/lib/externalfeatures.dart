import 'package:easy_localization/easy_localization.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:developer' as debug;

import '../tiles/tiles.dart';
import '../pages/device.dart';
import 'pages/settings.dart';

List<dynamic> features = List.empty(growable: true);

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

class Chart {
  String rawSelectedValue = "";
  String selectedValue = "";
  String selectedTimeframeTranslated = translatedTimeframes[0];
  String selectedTimeframe = remoteTimeframes[0];
  bool selectedTimeFrameChanged = false;
  List<String> rawOptions = List.empty(growable: true);
  List<String> translatedOptions = List.empty(growable: true);
  List<ListValue> data = List.empty(growable: true);
  String dataUnit = "";

  // EXPECTED DATA SHOULD BE IN THIS FORM: dd/mm/yyyy;hh:mm;sens1;sens2;sens3...
  // set the below values accordingly - if your data is in the form above, do not change them
  final int dayTimeIndex = 1;
  final int dayValueIndex = 4;
  Future<void> parseChartDaysData(String rawResponse) async
  {
    data = List.empty(growable: true);
    List<String> rawChartData = rawResponse.split("\n");
    rawChartData.removeAt(0);

    if (rawChartData.isNotEmpty)
    {
      for (String line in rawChartData) {
        List<String> parts = line.split(";");
        if (parts.length > 1) {
          try {
            String time = parts[dayTimeIndex];
            List<String> valueSplit = parts[dayValueIndex].split(" "); // used to remove the unit if present
            String value = valueSplit[0];
            if (valueSplit.length > 1) {
              dataUnit = valueSplit[1];
            }
            data.add(ListValue(time, double.tryParse(value) ?? 0.0));
          } catch (e) {
            debug.log("Error parsing line: $line, error: $e");
          }
        }
      }
    }
  }

  // EXPECTED DATA SHOULD BE IN THIS FORM: mm/yyyy;sens1;sens2;sens3...
  // set the below values accordingly - if your data is in the form above, do not change them
  final int monthDateIndex = 0;
  final int monthValueIndex = 3;
  Future<void> parseChartMonthsData(String rawResponse) async
  {
    data = List.empty(growable: true);
    List<String> rawChartData = rawResponse.split("\n");
    rawChartData.removeAt(0);

    if (rawChartData.isNotEmpty)
    {
      for (String line in rawChartData) {
        List<String> parts = line.split(";");
        if (parts.length > 1) {
          try {
            String date = parts[monthDateIndex];
            List<String> valueSplit = parts[monthValueIndex].split(" "); // used to remove the unit if present
            String value = valueSplit[0];
            if (valueSplit.length > 1) {
              dataUnit = valueSplit[1];
            }
            data.add(ListValue(date, double.tryParse(value) ?? 0.0));
          } catch (e) {
            debug.log("Error parsing line: $line, error: $e");
          }
        }
      }
    }
  }

  // EXPECTED DATA SHOULD BE IN THIS FORM: yyyy;sens1;sens2;sens3...
  // set the below values accordingly - if your data is in the form above, do not change them
  final int yearDateIndex = 0;
  final int yearValueIndex = 3;
  Future<void> parseChartYearsData(String rawResponse) async
  {
    data = List.empty(growable: true);
    List<String> rawChartData = rawResponse.split("\n");
    rawChartData.removeAt(0);

    if (rawChartData.isNotEmpty)
    {
      for (String line in rawChartData) {
        List<String> parts = line.split(";");
        if (parts.length > 1) {
          try {
            String date = parts[yearDateIndex];
            List<String> valueSplit = parts[yearValueIndex].split(" "); // used to remove the unit if present
            String value = valueSplit[0];
            if (valueSplit.length > 1) {
              dataUnit = valueSplit[1];
            }
            data.add(ListValue(date, double.tryParse(value) ?? 0.0));
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
    chart.parseChartDaysData(response);
  } else if (chart.selectedTimeframe == "months") {
    chart.parseChartMonthsData(response);
  } else if (chart.selectedTimeframe == "years") {
    chart.parseChartYearsData(response);
  }

  List<Widget> externalWidgets = List.empty(growable: true);

  if (!context.mounted) return List.empty(growable: false);

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
      // Chart title
      title: ChartTitle(text: chart.selectedValue),
      // Enable legend
      legend: const Legend(isVisible: true),
      // Enable tooltip
      tooltipBehavior: TooltipBehavior(enable: true),
      series: <CartesianSeries<ListValue, String>>[
        LineSeries<ListValue, String>(
          dataSource: chart.data,
          xValueMapper: (ListValue listValue, _) => listValue.time,
          yValueMapper: (ListValue listValue, _) => listValue.data,
          name: chart.dataUnit,
          // Enable data label
          //dataLabelSettings: const DataLabelSettings(isVisible: true)
        )
      ]
    )
  );
  // CHART

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

  //externalFeaturesListener.value = !externalFeaturesListener.value;
  return featuresToReturn;
}

void createExternalFeature(int id)
{
  if (id == chart) {
    features.add(Chart());
  }
}

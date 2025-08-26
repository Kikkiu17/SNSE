import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/*const ListTile loadingTile = ListTile(
  title: Padding(
    padding: EdgeInsets.all(8.0),
      child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 16),
        Text("Caricamento..."),
      ],
      ),
  )
);*/

ListTile loadingTile = ListTile(
    title: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 16),
      Text("loading_text".tr()),
    ],
  ),
);

const ListTile loadingTileNoText = ListTile(
    title: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ],
  ),
);

ListTile grayTextCenteredTile(String text) {
  return ListTile(
    title: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: const TextStyle(fontSize: 16, color: Colors.grey)),
      ],
    ),
  );
}
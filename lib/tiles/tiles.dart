import 'package:flutter/material.dart';

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

const ListTile loadingTile = ListTile(
    title: Row(
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
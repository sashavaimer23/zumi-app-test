import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme.dart';

/// QR-код каталога — для визиток, листовок, табличек «Сдаётся»
void showQr(BuildContext context, String link, String short) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Your catalogue QR code', style: TextStyle(color: Zc.green)),
      content: SizedBox(
        width: 280,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(
            data: link,
            size: 240,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1E4A3F)),
            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1E4A3F)),
          ),
          const SizedBox(height: 10),
          Text(short, style: const TextStyle(fontWeight: FontWeight.w600, color: Zc.green)),
          const SizedBox(height: 8),
          const Text('Take a screenshot and put it on your business card, flyer or a "To let" board. '
              'People point their phone camera at it and your catalogue opens.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Zc.grey, height: 1.4)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ),
  );
}

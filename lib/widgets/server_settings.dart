import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../core/config.dart';
import '../core/theme.dart';
import 'common.dart';

/// Choose which crickDbModule backend the app talks to.
Future<void> showServerSettings(BuildContext context, {VoidCallback? onChanged}) async {
  final ctrl = TextEditingController(text: AppConfig.apiBase);
  String? status;
  bool testing = false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      Future<void> test() async {
        setS(() {
          testing = true;
          status = null;
        });
        try {
          var base = ctrl.text.trim().replaceFirst(RegExp(r'/+$'), '');
          if (!base.endsWith('/api')) base = '$base/api';
          final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 8)))
              .get('$base/billing/plans');
          setS(() => status = r.statusCode == 200 ? '✓ Connected' : 'Server replied ${r.statusCode}');
        } catch (e) {
          setS(() => status = '✗ Not reachable — is crickDbModule running? ($e)');
        } finally {
          setS(() => testing = false);
        }
      }

      Widget preset(String label, String url) => ActionChip(label: Text(label), onPressed: () => setS(() => ctrl.text = url));
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Backend server', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text(
            'Run crickDbModule (npm start, port 8080). Emulator → 10.0.2.2; a real phone → your computer\'s Wi-Fi IP.',
            style: TextStyle(color: AppColors.textMid, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            preset('Local (emulator)', AppConfig.localEmulatorApi),
            preset('LAN IP…', 'http://192.168.1.10:8080/api'),
            preset('Cloud', AppConfig.cloudApi),
          ]),
          const SizedBox(height: 10),
          TextField(controller: ctrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'API base URL')),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(status!, style: TextStyle(color: status!.startsWith('✓') ? AppColors.success : AppColors.live, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: testing ? null : test, child: Text(testing ? 'Testing…' : 'Test connection'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  await AppConfig.setApiBase(ctrl.text);
                  if (c.mounted) Navigator.pop(c, true);
                },
                child: const Text('Save'),
              ),
            ),
          ]),
        ]),
      );
    }),
  );
  if (saved == true && context.mounted) {
    context.toast('Server set to ${AppConfig.apiBase}', success: true);
    onChanged?.call();
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class VpnEnforcementService {
  static final VpnEnforcementService instance = VpnEnforcementService._();
  VpnEnforcementService._();

  static const List<String> _vpnKeywords = [
    'vpn',
    'proxy',
    'hosting',
    'datacenter',
    'cloud',
    'm247',
    'ovh',
    'digitalocean',
    'linode',
    'aws',
    'amazon',
    'google',
    'azure',
    'fastly',
    'expressvpn',
    'nordvpn',
    'cyberghost',
    'surfshark',
    'proton',
    'hideme',
    'windscribe',
    'mullvad',
    'private internet access',
    'ipvanish',
    'vyprvpn',
    'tunnelbear',
    'zenmate',
    'hotspot shield',
    'purevpn',
    'strongvpn',
    'tor-exit',
    'anonymizer',
    'server',
    'cdn',
    'host',
  ];

  /// Checks if current network IP belongs to a VPN, Proxy, or Datacenter network.
  /// Returns a map with `isVpnDetected`, `isp`, `countryName`, `countryCode`.
  Future<Map<String, dynamic>> checkVpnLocation() async {
    // 1st Provider: ip-api.com
    try {
      final response = await http
          .get(Uri.parse('http://ip-api.com/json?fields=status,message,country,countryCode,isp,org,as,proxy,hosting,mobile,query'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final bool proxyFlag = data['proxy'] == true;
          final bool hostingFlag = data['hosting'] == true;
          final String isp = (data['isp'] ?? '').toString().toLowerCase();
          final String org = (data['org'] ?? '').toString().toLowerCase();
          final String asInfo = (data['as'] ?? '').toString().toLowerCase();
          final String countryName = data['country']?.toString() ?? 'Unknown';
          final String countryCode = data['countryCode']?.toString().toUpperCase() ?? '';

          bool keywordMatched = _vpnKeywords.any((keyword) =>
              isp.contains(keyword) || org.contains(keyword) || asInfo.contains(keyword));

          final bool isVpn = proxyFlag || hostingFlag || keywordMatched;
          return {
            'isVpnDetected': isVpn,
            'isp': data['isp'] ?? data['org'] ?? 'VPN/Proxy Provider',
            'countryCode': countryCode,
            'countryName': countryName,
          };
        }
      }
    } catch (e) {
      debugPrint('ip-api.com check error: $e');
    }

    // 2nd Provider: ipapi.co
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String org = (data['org'] ?? data['asn'] ?? '').toString().toLowerCase();
        final String countryName = data['country_name']?.toString() ?? '';
        final String countryCode = data['country_code']?.toString().toUpperCase() ?? '';

        final bool isVpn = _vpnKeywords.any((keyword) => org.contains(keyword));
        return {
          'isVpnDetected': isVpn,
          'isp': data['org'] ?? 'Network Provider',
          'countryCode': countryCode,
          'countryName': countryName,
        };
      }
    } catch (e) {
      debugPrint('ipapi.co check error: $e');
    }

    return {
      'isVpnDetected': false,
      'isp': 'Direct Network',
      'countryCode': 'DIRECT',
      'countryName': 'Direct Connection',
    };
  }

  /// Verifies network security before launching a task.
  /// Shows blocking alert dialog if a VPN / Proxy connection is detected.
  /// Returns `true` if VPN is OFF (allowed), `false` if VPN is ON (blocked).
  Future<bool> verifyVpnAndProceed(BuildContext context) async {
    // Show quick security verification dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.amber),
                SizedBox(height: 14),
                Text('Verifying Network Security...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await checkVpnLocation();
    if (context.mounted) {
      Navigator.pop(context); // Close checking indicator dialog
    }

    final bool isVpnDetected = result['isVpnDetected'] ?? false;
    final String ispName = result['isp'] ?? 'VPN/Proxy Network';

    if (!isVpnDetected) {
      return true; // Connection is clean (VPN is OFF)
    }

    // Show VPN Fraud Blocking Dialog if VPN is ON
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1F1B16) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.security_rounded, color: Colors.red, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'VPN Fraud Detected 🚫',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.red),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade400),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Active VPN / Proxy Detected ($ispName)',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'VPN and Proxy connections are strictly prohibited for tasks and payouts to prevent fraud.',
                  style: TextStyle(fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade800.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade600),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_rounded, color: Colors.amber.shade900, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Please TURN OFF your VPN / Proxy and use your direct mobile data or Wi-Fi to continue.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  verifyVpnAndProceed(context);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('I Turn OFF VPN (Re-check)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              ),
            ],
          );
        },
      );
    }

    return false;
  }
}

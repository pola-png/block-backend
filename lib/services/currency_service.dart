import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CurrencyInfo {
  final String currencyCode;
  final double rate;
  final double convertedAmount;

  CurrencyInfo({
    required this.currencyCode,
    required this.rate,
    required this.convertedAmount,
  });
}

class CurrencyService {
  static const Map<String, String> _countryToCurrency = {
    'NG': 'NGN',
    'GH': 'GHS',
    'KE': 'KES',
    'ZA': 'ZAR',
    'UG': 'UGX',
    'RW': 'RWF',
    'TZ': 'TZS',
    'EG': 'EGP',
  };

  static Future<String> detectUserCountry() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['country_code'] != null) {
          return data['country_code'].toString().toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Primary country detection failed: $e. trying fallback...');
    }

    try {
      final response = await http.get(Uri.parse('http://ip-api.com/json')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['countryCode'] != null) {
          return data['countryCode'].toString().toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Fallback country detection failed: $e');
    }

    return 'US'; // Default fallback
  }

  static Future<CurrencyInfo> getLocalCurrencyInfo(double amountInUsd) async {
    final country = await detectUserCountry();
    final currency = _countryToCurrency[country] ?? 'USD';

    if (currency == 'USD') {
      return CurrencyInfo(currencyCode: 'USD', rate: 1.0, convertedAmount: amountInUsd);
    }

    try {
      final response = await http.get(Uri.parse('https://open.er-api.com/v6/latest/USD')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['rates'] != null && data['rates'][currency] != null) {
          final double rate = (data['rates'][currency] as num).toDouble();
          return CurrencyInfo(
            currencyCode: currency,
            rate: rate,
            convertedAmount: amountInUsd * rate,
          );
        }
      }
    } catch (e) {
      debugPrint('Exchange rate fetch failed: $e');
    }

    return CurrencyInfo(currencyCode: 'USD', rate: 1.0, convertedAmount: amountInUsd);
  }
}

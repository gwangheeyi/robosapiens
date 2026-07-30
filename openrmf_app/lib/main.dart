import 'package:flutter/material.dart';

import 'src/app.dart';

void main() {
  const apiUrl = String.fromEnvironment(
    'RMF_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  const apiToken = String.fromEnvironment(
    'RMF_API_TOKEN',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiJzdHViIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiYWRtaW4iLCJpYXQiOjE1MTYyMzkwMjIsImF1ZCI6InJtZl9hcGlfc2VydmVyIiwiaXNzIjoic3R1YiIsImV4cCI6MjA1MTIyMjQwMH0.'
        'zzX3zXp467ldkzmLVIadQ_AHr8M5uWVV43n4wEB0OhE',
  );
  runApp(OpenRmfApp(apiUrl: apiUrl, apiToken: apiToken));
}

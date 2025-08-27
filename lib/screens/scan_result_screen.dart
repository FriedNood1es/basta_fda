import 'package:flutter/material.dart';

class ScanResultScreen extends StatelessWidget {
  final Map<String, String> productInfo;
  final String status;

  const ScanResultScreen({
    super.key,
    required this.productInfo,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Result")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ FDA Logo
            Center(
              child: Image.asset('assets/logo.png', height: 80),
            ),
            const SizedBox(height: 20),

            // ✅ Product Name
            Text(
              productInfo['brand_name'] ?? 'N/A',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // ✅ Registration & Status
            Text("Registration No.: ${productInfo['reg_no'] ?? 'N/A'}"),
            Text(
              "Status: $status",
              style: TextStyle(
                color: status == "VERIFIED" ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text("Last Updated: ${productInfo['issuance_date'] ?? 'N/A'}"),
            const Divider(height: 30),

            // ✅ Additional Info
            Text("Generic Name: ${productInfo['generic_name'] ?? 'N/A'}"),
            Text("Dosage Strength: ${productInfo['dosage_strength'] ?? 'N/A'}"),
            Text("Dosage Form: ${productInfo['dosage_form'] ?? 'N/A'}"),
            Text("Manufacturer: ${productInfo['manufacturer'] ?? 'N/A'}"),
            Text("Country: ${productInfo['country'] ?? 'N/A'}"),
            Text("Distributor: ${productInfo['distributor'] ?? 'N/A'}"),
            const SizedBox(height: 30),

            // ✅ Report Button
            Center(
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Report submitted")),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text("Report Suspicious Product"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

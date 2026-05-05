import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RootCauseVariantDemo extends StatefulWidget {
  final String apiBaseUrl;

  const RootCauseVariantDemo({Key? key, required this.apiBaseUrl})
      : super(key: key);

  @override
  State<RootCauseVariantDemo> createState() => _RootCauseVariantDemoState();
}

class _RootCauseVariantDemoState extends State<RootCauseVariantDemo> {
  bool _isLoading = false;
  Map<String, dynamic>? _simulationResult;
  String? _errorMessage;

  Future<void> _runSimulation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/simulations/root-cause-variants'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _simulationResult = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Failed to run simulation: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Root Cause Variant Demonstration'),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Card(
              color: Colors.lightBlue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Root Cause Variant System',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This demonstration shows how the system detects different root causes for the same error (Service Crash 1003) and applies targeted remediation for each variant.',
                      style: TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '✓ Same Error ID, Different Root Causes',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                    const Text(
                      '✓ Targeted Remediation Per Variant',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                    const Text(
                      '✓ Demonstrates Intelligent Classification',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Launch Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _runSimulation,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _isLoading
                      ? 'Running Simulation...'
                      : 'Simulate Root Cause Variants',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Error Message
            if (_errorMessage != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Results
            if (_simulationResult != null)
              _buildSimulationResults(_simulationResult!),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationResults(Map<String, dynamic> result) {
    final variants = result['variants'] as List<dynamic>? ?? [];
    final summary = result['summary'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline
        const SizedBox(height: 24),
        const Text(
          'Execution Timeline',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...(result['timeline'] as List<dynamic>? ?? []).map((step) {
          return _buildTimelineStep(step as Map<String, dynamic>);
        }).toList(),

        // Variant Results
        const SizedBox(height: 24),
        const Text(
          'Root Cause Variants Detected & Remediated',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...variants.map((variant) {
          return _buildVariantCard(variant as Map<String, dynamic>);
        }).toList(),

        // Summary
        const SizedBox(height: 24),
        Card(
          color: Colors.green[50],
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                ...(summary.entries).map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatKey(e.key),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          e.value.toString(),
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTimelineStep(Map<String, dynamic> step) {
    final title = step['title'] ?? '';
    final status = step['status'] ?? '';
    final detail = step['detail'] ?? '';

    Color statusColor = Colors.blue;
    IconData statusIcon = Icons.pending;

    if (status == 'completed') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (status == 'in_progress') {
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_bottom;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantCard(Map<String, dynamic> variant) {
    final variantNum = variant['variant_number'] ?? 0;
    final errorMessage = variant['error_message'] ?? '';
    final detectedVariant = variant['detected_variant'] as Map<String, dynamic>? ?? {};
    final matchedRule = variant['matched_rule'] as Map<String, dynamic>? ?? {};
    final remediation = variant['remediation'] as Map<String, dynamic>? ?? {};
    final result = variant['result'] ?? '';

    final variantLabel = detectedVariant['label'] ?? 'Unknown';
    final confidence = detectedVariant['confidence'] ?? 0;
    final ruleName = matchedRule['name'] ?? '';
    final remediationOutput = remediation['output'] ?? '';

    Color resultColor = Colors.orange;
    if (result.contains('✓')) {
      resultColor = Colors.green;
    } else if (result.contains('⚠')) {
      resultColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Variant #$variantNum',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(
                    '$confidence% Confidence',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                  backgroundColor: _getConfidenceColor(confidence),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Error Message
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Error Message:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorMessage,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Detected Variant
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detected Variant:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    variantLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Matched Rule
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Applied Rule:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ruleName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    matchedRule['action'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Remediation Output
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remediation Output:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    remediationOutput,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.greenAccent,
                      fontFamily: 'Courier New',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Result
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: resultColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: resultColor, width: 2),
              ),
              child: Row(
                children: [
                  Icon(
                    result.contains('✓')
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: resultColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: resultColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(dynamic confidence) {
    final conf = (confidence as num).toInt();
    if (conf >= 80) return Colors.green;
    if (conf >= 60) return Colors.orange;
    return Colors.red;
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

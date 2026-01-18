import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../widgets/gradient_scaffold.dart';

class LegalDocumentScreen extends StatefulWidget {
  final String title;
  final String docId;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.docId,
  });

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  String? _pdfUrl;
  bool _isLoading = true;
  String? _error;
  bool _hasCheckbox = false;
  bool _isAgreed = false;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc(widget.docId)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _pdfUrl = doc.data()?['pdfUrl'];
          _hasCheckbox = doc.data()?['hasCheckbox'] ?? false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Document not found.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading document: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
                    : _pdfUrl != null
                        ? SfPdfViewer.network(_pdfUrl!)
                        : const Center(child: Text('No document available.', style: TextStyle(color: Colors.white))),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Uses the composer's existing controller: closing this route retains the
/// draft, while only an explicit Post returns true to the existing send path.
class CommunityMessageEditor extends StatefulWidget {
  const CommunityMessageEditor({
    super.key,
    required this.controller,
    this.startInReview = false,
    this.attachmentCount = 0,
    this.isPoetry = false,
    this.attachmentPreviews,
    this.onAddImages,
    this.onRemoveImage,
    this.optionsBuilder,
    this.isPoetrySelected,
  });

  final TextEditingController controller;
  final bool startInReview;
  final int attachmentCount;
  final bool isPoetry;
  final List<Widget> Function()? attachmentPreviews;
  final Future<void> Function()? onAddImages;
  final ValueChanged<int>? onRemoveImage;
  final Widget Function(BuildContext context, VoidCallback refresh)? optionsBuilder;
  final bool Function()? isPoetrySelected;

  @override
  State<CommunityMessageEditor> createState() => _CommunityMessageEditorState();
}

class _CommunityMessageEditorState extends State<CommunityMessageEditor> {
  late bool _reviewing;
  bool _pickingImages = false;

  @override
  void initState() {
    super.initState();
    _reviewing = widget.startInReview;
  }

  void _review() {
    FocusScope.of(context).unfocus();
    setState(() => _reviewing = true);
  }

  Future<void> _addImages() async {
    if (_pickingImages) return;
    FocusScope.of(context).unfocus();
    setState(() => _pickingImages = true);
    try {
      await widget.onAddImages?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add images. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Widget _images(List<Widget> previews) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: previews.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
          width: 96,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: previews[index],
              ),
              if (widget.onRemoveImage != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filled(
                    tooltip: 'Remove image ${index + 1}',
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _pickingImages ? null : () {
                      widget.onRemoveImage!(index);
                      setState(() {});
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addImagesButton() => OutlinedButton.icon(
    onPressed: _pickingImages ? null : _addImages,
    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
    icon: const Icon(Icons.add_photo_alternate_outlined),
    label: Text(_pickingImages ? 'Adding...' : 'Add image'),
  );

  @override
  Widget build(BuildContext context) {
    final previews = widget.attachmentPreviews?.call() ?? const <Widget>[];
    final attachmentCount = widget.attachmentPreviews == null
      ? widget.attachmentCount : previews.length;
    final isPoetry = widget.isPoetrySelected?.call() ?? widget.isPoetry;
    return Scaffold(
      backgroundColor: const Color(0xFF17152A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17152A),
        foregroundColor: Colors.white,
        title: Text(_reviewing ? 'Review your message' : 'Write your message'),
        leading: IconButton(
          tooltip: 'Close and keep draft',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, layout) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (layout.maxHeight >= 340) Text(
                _reviewing
                    ? 'Check your message and images before posting.'
                    : 'Write freely, add images if you wish, then review before posting.',
                style: const TextStyle(color: Colors.white70),
              ),
              if (isPoetry || attachmentCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (isPoetry) 'Also sharing to Poetry',
                    if (attachmentCount > 0)
                      '$attachmentCount image${attachmentCount == 1 ? '' : 's'} attached',
                  ].join(' • '),
                  style: const TextStyle(color: Colors.amberAccent),
                ),
              ],
              if (widget.optionsBuilder != null) ...[
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: layout.maxHeight < 340 ? 64 : 112,
                  ),
                  child: SingleChildScrollView(
                    child: widget.optionsBuilder!(context, () {
                      if (mounted) setState(() {});
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: _reviewing
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SelectableText(
                            widget.controller.text.isEmpty
                                ? 'Image-only post'
                                : widget.controller.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.5,
                            ),
                              ),
                              if (previews.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _images(previews),
                              ],
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(builder: (context, constraints) => Column(
                        children: [
                          Expanded(child: TextField(
                        controller: widget.controller,
                        autofocus: true,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Your message or poem...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                          )),
                          if (previews.isNotEmpty && constraints.maxHeight > 220) ...[
                            const SizedBox(height: 8),
                            _images(previews),
                          ],
                        ],
                      )),
              ),
              const SizedBox(height: 12),
              if (_reviewing && widget.onAddImages != null) ...[
                _addImagesButton(),
                const SizedBox(height: 8),
              ],
              if (_reviewing)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _pickingImages ? null : () => setState(() => _reviewing = false),
                        child: const Text('Back to edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pickingImages || (widget.controller.text.trim().isEmpty &&
                          attachmentCount == 0)
                            ? null
                            : () => Navigator.pop(context, true),
                        icon: const Icon(Icons.send),
                        label: const Text('Post'),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    if (widget.onAddImages != null) ...[
                      Expanded(child: _addImagesButton()),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: FilledButton.icon(
                      onPressed: _pickingImages ? null : _review,
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Review'),
                    )),
                  ],
                ),
            ],
          )),
        ),
      ),
    );
  }
}
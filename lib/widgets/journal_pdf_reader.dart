import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../theme/east_design.dart';

/// Presents real rasterized Journal PDF pages as a restrained, page-by-page
/// EAST. reader.
///
/// PDF generation and rasterization remain owned by [PdfPreview]. This widget
/// only controls presentation: one A4 page is the hero at a time, adjacent
/// page edges quietly suggest horizontal movement, and a small folio provides
/// orientation without introducing toolbar chrome.
class JournalPdfReader extends StatefulWidget {
  const JournalPdfReader({
    super.key,
    required this.pages,
    required this.journalLabel,
  });

  final List<PdfPreviewPageData> pages;
  final String journalLabel;

  @override
  State<JournalPdfReader> createState() => _JournalPdfReaderState();
}

class _JournalPdfReaderState extends State<JournalPdfReader> {
  late final PageController _controller;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.90);
  }

  @override
  void didUpdateWidget(covariant JournalPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pageIndex < widget.pages.length) return;
    _pageIndex = widget.pages.isEmpty ? 0 : widget.pages.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(_pageIndex);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = EastColors.of(context);
    final pageCount = widget.pages.length;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            key: const ValueKey('journal-pdf-page-view'),
            controller: _controller,
            padEnds: true,
            itemCount: pageCount,
            onPageChanged: (index) => setState(() => _pageIndex = index),
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              return Semantics(
                container: true,
                image: true,
                label: '${widget.journalLabel} ${index + 1} / $pageCount',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: page.aspectRatio,
                        child: DecoratedBox(
                          key: ValueKey('journal-pdf-page-$index'),
                          decoration: BoxDecoration(
                            color: palette.background,
                            border: Border.all(
                              color: palette.divider.withValues(alpha: 0.72),
                              width: 0.5,
                            ),
                          ),
                          child: Image(
                            image: page.image,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: Text(
            '${(_pageIndex + 1).toString().padLeft(2, '0')}  /  '
            '${pageCount.toString().padLeft(2, '0')}',
            key: const ValueKey('journal-pdf-page-indicator'),
            style: EastTypography.localized(
              context,
              size: 11,
              color: palette.secondary,
              height: 1,
              letterSpacing: 2.2,
            ),
          ),
        ),
      ],
    );
  }
}

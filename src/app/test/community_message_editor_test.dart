import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_user_app/widgets/community_message_editor.dart';

void main() {
  Future<void> openEditor(
    WidgetTester tester,
    TextEditingController controller, {
    bool review = false,
    int attachments = 0,
    ValueChanged<bool?>? onResult,
    List<Widget> Function()? previews,
    Future<void> Function()? addImages,
    ValueChanged<int>? removeImage,
    Widget Function(BuildContext, VoidCallback)? optionsBuilder,
    bool Function()? poetrySelected,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => CommunityMessageEditor(
                controller: controller,
                startInReview: review,
                attachmentCount: attachments,
                attachmentPreviews: previews,
                onAddImages: addImages,
                onRemoveImage: removeImage,
                optionsBuilder: optionsBuilder,
                isPoetrySelected: poetrySelected,
              )),
            );
            onResult?.call(result);
          },
          child: const Text('Open editor'),
        ),
      )),
    ));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  testWidgets('multiline poem can be reviewed and edited without posting', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    bool? result;
    await openEditor(tester, controller, onResult: (value) => result = value);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, isNull);
    expect(field.textInputAction, TextInputAction.newline);
    const poem = 'First line\n\nSecond stanza\nFinal line';
    await tester.enterText(find.byType(TextField), poem);
    expect(find.text('Post'), findsNothing);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, poem);
    expect(result, isNull);
    await tester.tap(find.text('Back to edit'));
    await tester.pumpAndSettle();
    expect(controller.text, poem);
    await tester.tap(find.byTooltip('Close and keep draft'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(controller.text, poem);
  });

  testWidgets('only explicit Post returns permission to submit', (tester) async {
    final controller = TextEditingController(text: 'Reviewed message');
    addTearDown(controller.dispose);
    bool? result;
    await openEditor(tester, controller, review: true, onResult: (value) => result = value);
    expect(result, isNull);
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(controller.text, 'Reviewed message');
  });

  testWidgets('empty text cannot post without an image', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await openEditor(tester, controller, review: true);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNull);
  });

  testWidgets('image-only review can post and retains attachment context', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await openEditor(tester, controller, review: true, attachments: 2);
    expect(find.text('2 images attached'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNotNull);
  });

  testWidgets('long poem remains scrollable on a small phone with keyboard', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final controller = TextEditingController(text: List.filled(60, 'A long poem line').join('\n'));
    addTearDown(controller.dispose);
    await openEditor(tester, controller);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('images can be added while writing and retained when closing', (tester) async {
    final controller = TextEditingController(text: 'Poem\nSecond line');
    addTearDown(controller.dispose);
    final images = <Widget>[];
    bool? result;
    await openEditor(tester, controller,
      previews: () => images,
      addImages: () async => images.add(const Icon(Icons.image, key: ValueKey('draft-photo'))),
      removeImage: images.removeAt,
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('Add image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-photo')), findsOneWidget);
    expect(find.text('1 image attached'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-photo')), findsOneWidget);
    expect(controller.text, 'Poem\nSecond line');
    await tester.tap(find.byTooltip('Close and keep draft'));
    await tester.pumpAndSettle();
    expect(images, hasLength(1));
    expect(result, isFalse);
  });

  testWidgets('review can add and remove images without posting', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final images = <Widget>[];
    bool? result;
    await openEditor(tester, controller, review: true,
      previews: () => images,
      addImages: () async => images.add(const Icon(Icons.image, key: ValueKey('review-photo'))),
      removeImage: images.removeAt,
      onResult: (value) => result = value,
    );
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNull);
    await tester.tap(find.text('Add image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-photo')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNotNull);
    expect(result, isNull);
    await tester.tap(find.byTooltip('Remove image 1'));
    await tester.pumpAndSettle();
    expect(images, isEmpty);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNull);
    expect(result, isNull);
  });

  testWidgets('existing thumbnails and draft survive a cancelled image picker', (tester) async {
    final controller = TextEditingController(text: 'Keep this message');
    addTearDown(controller.dispose);
    final images = <Widget>[const Icon(Icons.image, key: ValueKey('existing-photo'))];
    await openEditor(tester, controller, review: true,
      previews: () => images,
      addImages: () async {},
      removeImage: images.removeAt,
    );
    await tester.tap(find.text('Add image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('existing-photo')), findsOneWidget);
    expect(controller.text, 'Keep this message');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Poetry selection and agreement cancellation remain in the popup', (tester) async {
    final controller = TextEditingController(text: 'My poem');
    addTearDown(controller.dispose);
    var selected = false;
    var agree = false;
    await openEditor(tester, controller,
      poetrySelected: () => selected,
      optionsBuilder: (context, refresh) => CheckboxListTile(
        title: const Text('Add your Poem'),
        value: selected,
        onChanged: (value) async {
          final accepted = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Poetry rules'),
              actions: [TextButton(
                onPressed: () => Navigator.pop(dialogContext, agree),
                child: const Text('Decide'),
              )],
            ),
          );
          selected = accepted == true;
          refresh();
        },
      ),
    );
    await tester.tap(find.text('Add your Poem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decide'));
    await tester.pumpAndSettle();
    expect(selected, isFalse);
    agree = true;
    await tester.tap(find.text('Add your Poem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decide'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Also sharing to Poetry'), findsOneWidget);
    expect(find.text('My poem'), findsOneWidget);
  });

  testWidgets('hidden Poetry option leaves editor and review balanced', (tester) async {
    final controller = TextEditingController(text: 'Ordinary post');
    addTearDown(controller.dispose);
    await openEditor(tester, controller,
      optionsBuilder: (_, _) => const SizedBox.shrink(),
      poetrySelected: () => false,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Also sharing to Poetry'), findsNothing);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image controls fit a small phone with keyboard', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final controller = TextEditingController(text: 'Poem');
    addTearDown(controller.dispose);
    await openEditor(tester, controller,
      previews: () => [const Icon(Icons.image)],
      addImages: () async {},
      removeImage: (_) {},
      poetrySelected: () => true,
      optionsBuilder: (_, _) => Column(children: [
        CheckboxListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Add your Poem'),
        ),
        CheckboxListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Save selected images to My Harmony Vault as well'),
        ),
      ]),
    );
    expect(find.text('Add image'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
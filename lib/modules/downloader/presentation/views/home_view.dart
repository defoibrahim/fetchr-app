import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../app/shared/download_prefs_provider.dart';
import '../../../../app/shared/yt_dlp_provider.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/gen/assets.gen.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/utils/widget_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/error_card.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/extensions/string_extensions.dart';
import '../providers/clipboard_suggestion_notifier.dart';
import '../providers/home_notifier.dart';
import 'widgets/clipboard_suggestion.dart';
import 'widgets/convert_video_tile.dart';
import 'widgets/fetch_error_card.dart';
import 'widgets/format_sheet.dart';
import 'widgets/home_header.dart';
import 'widgets/home_recent.dart';
import 'widgets/url_field.dart';

const _heroGap = 20.0;
const _sublineGap = 6.0;
const _inputGap = 22.0;
const _narrowHero = 30.0;

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  String _lastText = '';

  // The pre-check found the picked quality too big. The fetched info stays in
  // the notifier so Lower quality can reopen the sheet on it.
  ({Quality quality, int needed, int free})? _storage;
  bool _sheetOpen = false;

  HomeNotifier get _notifier => ref.read(homeNotifierProvider.notifier);

  ClipboardSuggestionNotifier get _clipboard =>
      ref.read(clipboardSuggestionProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onFieldChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    unawaited(_listenForShares());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shareSub?.cancel());
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After a frame: Android 10+ hides the clipboard until the window has focus.
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    }
  }

  Future<void> _listenForShares() async {
    final sharing = ReceiveSharingIntent.instance;
    _shareSub = sharing.getMediaStream().listen(
      _onShared,
      onError: (Object e, StackTrace s) =>
          AppLogger.error('Share stream failed', e, s),
    );
    try {
      final initial = await sharing.getInitialMedia();
      _onShared(initial);
    } catch (e, s) {
      AppLogger.error('Could not read the shared link', e, s);
    }
  }

  void _onShared(List<SharedMediaFile> files) {
    final url = files.map((f) => f.path.firstUrl).nonNulls.firstOrNull;
    if (url == null || !mounted) return;
    // A hidden tab pauses this screen's listeners, so the sheet would wait
    // for the user to open Home.
    context.go(AppRoutes.home);
    _setUrl(url);
    _fetch();
    // Without this the same share is delivered again next launch.
    unawaited(
      ReceiveSharingIntent.instance.reset().catchError((
        Object e,
        StackTrace s,
      ) {
        AppLogger.error('Could not reset the shared link', e, s);
      }),
    );
  }

  Future<String?> _clipboardText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e, s) {
      AppLogger.error('Could not read the clipboard', e, s);
      return null;
    }
  }

  Future<void> _checkClipboard() async {
    final text = await _clipboardText();
    if (!mounted) return;
    _clipboard.check(clipboardText: text, fieldText: _controller.text);
  }

  Future<void> _paste() async {
    final text = (await _clipboardText())?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    _setUrl(text.firstUrl ?? text);
  }

  void _setUrl(String url) {
    _controller.value = TextEditingValue(
      text: url,
      selection: TextSelection.collapsed(offset: url.length),
    );
  }

  void _useSuggestion() {
    final url = _clipboard.take();
    if (url != null) _setUrl(url);
  }

  void _onFieldChanged() {
    final text = _controller.text;
    if (text == _lastText) return;
    _lastText = text;
    _clipboard.fieldChanged(text);
    _dismissError();
  }

  /// Editing the link clears the error card; a fetch in flight is left alone.
  void _dismissError() {
    final home = ref.read(homeNotifierProvider);
    if (home.isLoading || (_storage == null && !home.hasError)) return;
    setState(() => _storage = null);
    _notifier.clear();
  }

  void _fetch() {
    final url = _controller.text.firstUrl;
    if (url == null || _sheetOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _storage = null);
    // Riverpod keeps the last result through AsyncLoading; clearing first
    // means nothing reads a stale video or error while this one loads.
    _notifier.clear();
    unawaited(_notifier.fetch(url));
    unawaited(_openSheet());
  }

  void _onHomeState(
    AsyncValue<MediaInfo?>? previous,
    AsyncValue<MediaInfo?> next,
  ) {
    if (next.isLoading || !_sheetOpen) return;
    // Neither a failure nor a playlist is chosen in the sheet: close it, and
    // `_afterSheet` carries on from the state.
    if (next.hasError || (next.value?.isPlaylist ?? false)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _openSheet({Quality? preselect}) async {
    _sheetOpen = true;
    final Quality? chosen;
    try {
      chosen = await showAppBottomSheet<Quality>(
        context,
        child: FormatSheet(
          initialQuality: ref.read(downloadPrefsProvider).quality,
          preselect: preselect,
        ),
      );
    } finally {
      _sheetOpen = false;
    }
    if (!mounted) return;
    await _afterSheet(chosen);
  }

  Future<void> _afterSheet(Quality? chosen) async {
    final home = ref.read(homeNotifierProvider);
    // Dismissed while still fetching: drop the fetch, keep the link.
    if (home.isLoading) return _notifier.clear();
    // The failure card shows from the state.
    if (home.hasError) return;
    final info = home.value;
    if (info == null) return;
    if (info.isPlaylist) return _openPlaylist(info);
    if (chosen == null) return _notifier.clear();
    await _download(info, chosen);
  }

  Future<void> _openPlaylist(MediaInfo info) async {
    final added = await context.push<int>(AppRoutes.playlist, extra: info);
    if (!mounted) return;
    _notifier.clear();
    if (added == null) return;
    _controller.clear();
    _showAdded('${plural(added, 'video')} added to Downloads');
  }

  Future<void> _download(MediaInfo info, Quality quality) async {
    final shortfall = await _notifier.storageShortfall(info, quality);
    if (!mounted) return;
    if (shortfall != null) {
      setState(
        () => _storage = (
          quality: quality,
          needed: shortfall.needed,
          free: shortfall.free,
        ),
      );
      return;
    }
    final result = await _notifier.download(info, quality);
    if (!mounted) return;
    // Consume the result so the same link can be fetched again.
    _notifier.clear();
    if (result.isOk) {
      // A link shared while the sheet was open stays for the next fetch.
      if (_controller.text.firstUrl == info.url) _controller.clear();
      _showAdded('Added to Downloads');
    }
    await AppSnackbar.showFailure(context, result);
  }

  Future<void> _convertVideo() async {
    final result = await _notifier.convertVideo();
    if (!mounted) return;
    if (result case Ok(value: true)) _showAdded('Converting to MP3');
    await AppSnackbar.showFailure(context, result);
  }

  void _showAdded(String message) => AppSnackbar.show(
    context,
    message,
    type: SnackType.success,
    action: ('View', () => context.go(AppRoutes.downloads)),
  );

  Future<void> _updateYtDlp() async {
    final result = await ref.read(ytDlpProvider.notifier).updateYtDlp();
    if (!mounted) return;
    switch (result) {
      case Ok():
        _fetch();
      case Err(:final failure):
        AppSnackbar.show(context, failure.message, type: SnackType.error);
    }
  }

  void _editLink() {
    _focus.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _anotherLink() {
    _controller.clear();
    _focus.requestFocus();
  }

  /// Reopens the sheet on the info already fetched, with the option below the
  /// one that did not fit picked.
  void _lowerQuality() {
    final tried = _storage?.quality;
    final info = ref.read(homeNotifierProvider).value;
    if (tried == null || info == null) return;
    final next = info.optionBelow(tried)?.quality;
    setState(() => _storage = null);
    unawaited(_openSheet(preselect: next));
  }

  Failure? _failureOf(AsyncValue<MediaInfo?> home) {
    if (_storage != null) return const StorageFailure();
    final error = home.error;
    if (error == null || home.isLoading) return null;
    return error is Failure ? error : failureFrom(error);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(homeNotifierProvider, _onHomeState);
    final home = ref.watch(homeNotifierProvider);
    final phase = ref.watch(
      ytDlpProvider.select(
        (state) => state.value?.phase ?? YtDlpUpdatePhase.idle,
      ),
    );
    final failure = _failureOf(home);
    final suggestion = ref.watch(clipboardSuggestionProvider);
    final gutter = context.gutter;
    final type = context.type;
    final muted = context.tokens.textMuted;
    final storage = _storage;
    return SafeArea(
      child: CenteredContent(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, Gap.sm.h, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HomeHeader(),
                    SizedBox(height: _heroGap.h),
                    Text(
                      'Paste a link.\nGet the file.',
                      style: context.isNarrow
                          ? type.hero.copyWith(fontSize: _narrowHero)
                          : type.hero,
                    ),
                    SizedBox(height: _sublineGap.h),
                    Text(
                      'Or share any video to Fetchr from another app.',
                      style: type.body.copyWith(color: muted),
                    ),
                    SizedBox(height: _inputGap.h),
                    Text(
                      'VIDEO OR PLAYLIST URL',
                      style: type.overline.copyWith(color: muted),
                    ),
                    SizedBox(height: Gap.md.h),
                    UrlField(
                      controller: _controller,
                      focusNode: _focus,
                      hasError: failure != null,
                      onPaste: _paste,
                      onClear: _controller.clear,
                    ),
                    SizedBox(height: Gap.md.h),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (_, value, _) => AppButton(
                        label: 'Get formats',
                        icon: Assets.icons.arrowRight,
                        iconAfter: true,
                        isLoading: home.isLoading,
                        loadingLabel: 'Fetching…',
                        onPressed: value.text.firstUrl == null ? null : _fetch,
                      ),
                    ),
                    ClipboardSuggestion(
                      url: failure == null ? suggestion : null,
                      onUse: _useSuggestion,
                    ),
                    if (failure != null)
                      Padding(
                        padding: EdgeInsets.only(top: Gap.lg.h),
                        child: ErrorCard(
                          data: fetchErrorCard(
                            failure,
                            storage: storage == null
                                ? null
                                : (needed: storage.needed, free: storage.free),
                            ytDlpPhase: phase,
                            actions: FetchErrorActions(
                              updateYtDlp: () => unawaited(_updateYtDlp()),
                              editLink: _editLink,
                              anotherLink: _anotherLink,
                              retry: _fetch,
                              lowerQuality: _lowerQuality,
                              openLibrary: () => context.go(AppRoutes.library),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(height: Gap.lg.h),
                    ConvertVideoTile(onTap: () => unawaited(_convertVideo())),
                  ],
                ),
              ),
            ),
            HomeRecent(gutter: gutter),
          ],
        ),
      ),
    );
  }
}

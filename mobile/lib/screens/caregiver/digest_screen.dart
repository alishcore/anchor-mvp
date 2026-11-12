import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/call_helpers.dart';
import '../../widgets/hub.dart';
import '../../widgets/status_banner.dart';

/// The weekly digest a caregiver may read: up to three approved highlights and a
/// call action. Everything else — conversations, memories, raw observations —
/// stays private because the backend refuses it (SPEC §4).
///
/// Redesign 2026-11-11: the highlights are the page; the period is a small rule
/// above them, and the one filled action is the phone call at the bottom.
class DigestScreen extends StatefulWidget {
  const DigestScreen({super.key, required this.state});

  final AppState state;

  @override
  State<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<DigestScreen> {
  bool _loading = false;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_loading) return;
    setState(() => _loading = true);
    // Always re-fetch: current consent may have changed since this screen opened.
    await widget.state.loadDigests();
    await widget.state.loadNotifications();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _callCheckIn(AppState state, Contact contact) async {
    await dialWithConfirmation(
      context,
      l: state.l,
      label: contact.label,
      phone: contact.phone,
      dial: () => state.callContact(contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AnchorScope.of(context);
    final l = state.l;
    final selected = state.digests.where((d) => d.id == _selectedId);
    final digest = selected.isNotEmpty
        ? selected.first
        : state.digests.isEmpty
        ? null
        : state.digests.first;
    final contact = state.digestContact;
    final period = digest == null || digest.periodStart == null
        ? null
        : '${digest.periodStart} – ${digest.periodEnd ?? ''}';

    return Scaffold(
      appBar: AppBar(
        title: Text(l.caregiverDigestTitle),
        actions: [
          IconButton(
            key: const Key('refresh-digests'),
            tooltip: l.retry,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_loading) ...<Widget>[
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 8),
                const SizedBox(height: 14),
              ],
              if (state.offline)
                StatusBanner(
                  l: l,
                  title: l.offlineTitle,
                  body: l.caregiverNoDigest,
                  onRetry: _load,
                ),
              if (state.lastError != null && !state.offline)
                StatusBanner(
                  l: l,
                  tone: BannerTone.problem,
                  title: state.lastErrorText ?? l.unknownError,
                  onRetry: _load,
                ),
              Text(
                l.t(
                  '在同一网络连接时刷新查看。此版本不发送手机推送。',
                  'Refresh while connected to the same network. This version does not send push notifications.',
                ),
              ),
              for (final notice in state.notifications.where(
                (n) => n.kind == 'digest_ready' && n.isUnread,
              ))
                ListTile(
                  key: ValueKey('digest-notice-${notice.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.t('有新的家人简报', 'A family update is ready')),
                  trailing: TextButton(
                    onPressed: () => state.markNotificationRead(notice.id),
                    child: Text(l.t('标为已读', 'Mark read')),
                  ),
                ),
              if (state.digests.length > 1) ...[
                HubSectionLabel(label: l.t('选择一个星期', 'Choose a week')),
                for (final week in state.digests)
                  OutlinedButton(
                    key: ValueKey('select-digest-${week.id}'),
                    onPressed: () => setState(() => _selectedId = week.id),
                    child: Text(
                      '${week.periodStart ?? ""} — ${week.periodEnd ?? ""}',
                    ),
                  ),
              ],
              if (state.digestFeatureMissing)
                _quiet(l.caregiverDigestUnavailable)
              else if (digest == null)
                _quiet(
                  state.digestNote == 'insufficient_information'
                      ? l.caregiverInsufficient
                      : l.caregiverNoDigest,
                )
              else if (digest.isInsufficientData)
                _quiet(l.caregiverInsufficient)
              else ...<Widget>[
                if (period != null) ...<Widget>[
                  HubSectionLabel(label: period),
                  const SizedBox(height: 2),
                ],
                for (var index = 0; index < digest.highlights.length; index++)
                  _HighlightCard(
                    key: ValueKey<String>('highlight-$index'),
                    index: index,
                    item: digest.highlights[index],
                    l: l,
                  ),
                if (digest.highlights.isEmpty) _quiet(l.caregiverInsufficient),
              ],
              const SizedBox(height: 8),
              HubPrimaryButton(
                key: const Key('caregiver-call-checkin'),
                icon: Icons.phone_in_talk,
                label: contact == null
                    ? l.caregiverCallCheckin
                    : '${l.caregiverCallCheckin} · ${contact.label}',
                onPressed: contact == null
                    ? null
                    : () => _callCheckIn(state, contact),
              ),
              if (contact == null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  l.caregiverNoDigestContact,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AnchorTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              HubFooterNote(text: l.caregiverPrivacy),
            ],
          ),
        ),
      ),
    );
  }

  /// A sentence in a quiet panel, for every state where there is nothing to show
  /// yet. Never a blank page and never an invented highlight.
  Widget _quiet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HubPanel(
        tone: HubTone.ochre,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 24,
            color: AnchorTheme.ink,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    super.key,
    required this.index,
    required this.item,
    required this.l,
  });

  final int index;
  final DigestItem item;
  final L l;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnchorTheme.paperRaised,
        borderRadius: BorderRadius.circular(AnchorTheme.panelRadius),
        border: Border.all(color: AnchorTheme.line, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE7EFE9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: AnchorTheme.jade,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.topicLabel(item.topic),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ochre,
                    letterSpacing: 0.6,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.text, style: AnchorTheme.reading),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

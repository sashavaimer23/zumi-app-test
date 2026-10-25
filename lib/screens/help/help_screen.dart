import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';
import '../auth_screen.dart';
import '../shell.dart';
import '../support/support_screen.dart';
import '../support/ticket_chat_screen.dart';

// ======================================================================
// Помощь: статьи из базы (команда правит их в кабинете без обновления приложения),
// поиск, «Статья была полезной?», обращение в поддержку.
// ======================================================================

IconData helpIcon(String category) => switch (category) {
      'account' => ZI.user,
      'listings' => ZI.house,
      'contact' => ZI.chat,
      'verification' => ZI.verified,
      'promotion' => ZI.bolt,
      'safety' => ZI.shield,
      _ => ZI.settings,
    };

/// Поля по бокам: на широком экране текст не шире 760 px — его удобно читать
double _side(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w > 800 ? (w - 760) / 2 : 18;
}

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  late Future<List<HelpArticle>> _future = context.read<AppState>().repo.helpArticles();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _contactSupport() async {
    if (!await _ensureSignedIn(context, 'Sign in to write to the Zumi team.')) return;
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
  }

  Future<void> _replayTutorial() async {
    final app = context.read<AppState>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    Shell.current?.go(0);
    await app.resetHints();
  }

  @override
  Widget build(BuildContext context) {
    final side = _side(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: FutureBuilder<List<HelpArticle>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Zc.orange));
          }
          final all = snap.data ?? const <HelpArticle>[];
          // сначала статьи, где слова есть в заголовке
          final found = _query.trim().length < 2
              ? null
              : (all.where((a) => a.matches(_query)).toList()
                ..sort((a, b) => (b.title.toLowerCase().contains(_query.trim().toLowerCase()) ? 1 : 0)
                    .compareTo(a.title.toLowerCase().contains(_query.trim().toLowerCase()) ? 1 : 0)));
          return RefreshIndicator(
            color: Zc.orange,
            onRefresh: () async {
              setState(() => _future = context.read<AppState>().repo.helpArticles());
              await _future;
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(side, 6, side, 40),
              children: [
                Text('How can we help?', style: zHeadline(context, size: 28)),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search: code, number, scam, verified…',
                    prefixIcon: const Icon(ZI.search, color: Zc.grey),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(ZI.close, color: Zc.grey),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                if (snap.hasError)
                  EmptyState(icon: ZI.warning, title: 'Could not load help', subtitle: '${snap.error}')
                else if (found != null) ...[
                  Text(found.isEmpty ? 'Nothing found' : '${found.length} ${found.length == 1 ? 'article' : 'articles'}',
                      style: const TextStyle(color: Zc.grey)),
                  const SizedBox(height: 6),
                  for (final a in found) _ArticleTile(a: a, showCategory: true),
                  if (found.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Try other words, or write to the Zumi team below.', style: TextStyle(color: Zc.grey)),
                    ),
                ] else
                  for (final cat in helpCategories.keys)
                    if (all.any((a) => a.category == cat)) _CategoryBlock(category: cat, articles: [
                      for (final a in all)
                        if (a.category == cat) a,
                    ]),
                const SizedBox(height: 22),
                // не нашли ответ
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Did not find an answer?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Write to the Zumi team — we usually reply within a day.',
                        style: TextStyle(color: Zc.grey, height: 1.4)),
                    const SizedBox(height: 12),
                    PrimaryButton(label: 'Contact support', width: double.infinity, onPressed: _contactSupport),
                  ]),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(ZI.sparkle, color: Zc.green),
                  title: const Text('Show the tutorial again'),
                  subtitle: const Text('The short tour of the app and the first-time tips',
                      style: TextStyle(fontSize: 12, color: Zc.grey)),
                  onTap: _replayTutorial,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Вход перед обращением в поддержку
Future<bool> _ensureSignedIn(BuildContext context, String reason) async {
  if (context.read<AppState>().signedIn) return true;
  final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AuthScreen(reason: reason)));
  return ok == true;
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({required this.category, required this.articles});
  final String category;
  final List<HelpArticle> articles;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          leading: CircleAvatar(
            backgroundColor: Zc.chip,
            child: Icon(helpIcon(category), color: Zc.green, size: 20),
          ),
          title: Text(helpCategories[category] ?? category, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${articles.length} ${articles.length == 1 ? 'article' : 'articles'}',
              style: const TextStyle(fontSize: 12, color: Zc.grey)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [for (final a in articles) _ArticleTile(a: a)],
        ),
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.a, this.showCategory = false});
  final HelpArticle a;
  final bool showCategory;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(a.title, style: const TextStyle(fontSize: 15)),
        subtitle: showCategory ? Text(a.categoryLabel, style: const TextStyle(fontSize: 12, color: Zc.grey)) : null,
        trailing: const Icon(ZI.caretRight, size: 18, color: Zc.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HelpArticleScreen(article: a))),
      );
}

// ======================================================================
// Статья
// ======================================================================
class HelpArticleScreen extends StatefulWidget {
  const HelpArticleScreen({super.key, required this.article});
  final HelpArticle article;

  @override
  State<HelpArticleScreen> createState() => _HelpArticleScreenState();
}

class _HelpArticleScreenState extends State<HelpArticleScreen> {
  bool? _vote; // null — ещё не голосовал
  bool _commentSent = false;
  bool _sending = false;
  final _comment = TextEditingController();

  HelpArticle get a => widget.article;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _sendVote(bool helpful, {String? comment}) async {
    setState(() => _sending = true);
    try {
      await context.read<AppState>().repo.voteHelp(a.id, helpful, comment: comment);
      if (!mounted) return;
      setState(() {
        _vote = helpful;
        if (comment != null) _commentSent = true;
      });
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Обращение в поддержку с пометкой, какая статья не помогла
  Future<void> _writeToSupport() async {
    if (!await _ensureSignedIn(context, 'Sign in to write to the Zumi team.')) return;
    if (!mounted) return;
    final app = context.read<AppState>();
    final text = _comment.text.trim();
    final message = text.isEmpty ? 'The help article "${a.title}" did not answer my question.' : text;
    setState(() => _sending = true);
    try {
      if (_vote == null || (text.isNotEmpty && !_commentSent)) {
        await app.repo.voteHelp(a.id, false, comment: text.isEmpty ? null : text);
      }
      final subject = 'Help: ${a.title}';
      final id = await app.repo.openTicket(
        category: 'question',
        subject: subject.length > 140 ? subject.substring(0, 140) : subject,
        message: message,
        helpArticleId: a.id,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TicketChatScreen(
            ticket: SupportTicket(
              id: id,
              userId: app.user!.id,
              userName: app.user!.fullName,
              category: 'question',
              subject: subject,
              status: 'open',
              lastMessage: message,
              lastMessageAt: DateTime.now(),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = _side(context);
    return Scaffold(
      appBar: AppBar(title: Text(a.categoryLabel, style: const TextStyle(fontSize: 16))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 6, side, 40),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: zHeadline(context, size: 26)),
              const SizedBox(height: 14),
              HelpBody(text: a.body),
              const SizedBox(height: 26),
              const Divider(color: Zc.lightGrey),
              const SizedBox(height: 14),
              _feedback(),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _feedback() {
    if (_vote == true) {
      return const Row(children: [
        Icon(ZI.checkCircle, color: Zc.green),
        SizedBox(width: 8),
        Text('Thank you for your feedback!', style: TextStyle(color: Zc.green, fontWeight: FontWeight.w600)),
      ]);
    }
    if (_vote == false) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Sorry this did not help.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('What was missing? (optional) — it helps us improve the article.',
            style: TextStyle(color: Zc.grey)),
        const SizedBox(height: 10),
        TextField(
          controller: _comment,
          enabled: !_commentSent,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(hintText: 'Your comment'),
        ),
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (!_commentSent)
            OutlinedButton(
              onPressed: _sending
                  ? null
                  : () {
                      final t = _comment.text.trim();
                      if (t.isEmpty) {
                        showSnack(context, 'Write a few words, or contact support below');
                        return;
                      }
                      _sendVote(false, comment: t);
                    },
              child: const Text('Send comment'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Comment sent — thank you!', style: TextStyle(color: Zc.green)),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Zc.orange),
            onPressed: _sending ? null : _writeToSupport,
            icon: const Icon(ZI.chat, size: 18),
            label: const Text('Write to support'),
          ),
        ]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Was this article helpful?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Row(children: [
        OutlinedButton.icon(
          onPressed: _sending ? null : () => _sendVote(true),
          icon: const Icon(ZI.check, size: 18),
          label: const Text('Yes'),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _sending ? null : () => _sendVote(false),
          icon: const Icon(ZI.close, size: 18),
          label: const Text('No'),
        ),
      ]),
    ]);
  }
}

/// Текст статьи: абзацы через пустую строку, «## » — подзаголовок, «- » — пункт списка
class HelpBody extends StatelessWidget {
  const HelpBody({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 10));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(line.substring(3), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Zc.green)),
        ));
      } else if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 8, right: 10, left: 4),
              child: CircleAvatar(radius: 3, backgroundColor: Zc.orange),
            ),
            Expanded(child: Text(line.substring(2), style: const TextStyle(fontSize: 15, height: 1.5))),
          ]),
        ));
      } else {
        widgets.add(Text(line, style: const TextStyle(fontSize: 15, height: 1.5)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}

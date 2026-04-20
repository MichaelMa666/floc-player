import 'package:flutter/material.dart';

import '../models/channel.dart';

class LiveChannelCard extends StatelessWidget {
  const LiveChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
  });

  final Channel channel;
  final VoidCallback onTap;

  String _fmtStart(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 160,
                height: 90,
                child: _Cover(url: channel.coverUrl),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          channel.competitionName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmtStart(channel.startTime),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _MatchLine(
                    homeName: channel.homeTeamName,
                    homeLogo: channel.homeTeamLogo,
                    awayName: channel.awayTeamName,
                    awayLogo: channel.awayTeamLogo,
                  ),
                  if (channel.commentatorName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _CommentatorChip(
                      name: channel.commentatorName,
                      avatar: channel.commentatorAvatar,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(color: const Color(0xFF222222));
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: const Color(0xFF222222)),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(color: const Color(0xFF181818));
      },
    );
  }
}

class _MatchLine extends StatelessWidget {
  const _MatchLine({
    required this.homeName,
    required this.homeLogo,
    required this.awayName,
    required this.awayLogo,
  });

  final String homeName;
  final String homeLogo;
  final String awayName;
  final String awayLogo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TeamBlock(name: homeName, logo: homeLogo, alignEnd: true),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'VS',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white38,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: _TeamBlock(name: awayName, logo: awayLogo, alignEnd: false),
        ),
      ],
    );
  }
}

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({
    required this.name,
    required this.logo,
    required this.alignEnd,
  });

  final String name;
  final String logo;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final nameText = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
    final logoWidget = logo.isNotEmpty
        ? SizedBox(
            width: 16,
            height: 16,
            child: Image.network(
              logo,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          )
        : const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: alignEnd
          ? [nameText, const SizedBox(width: 4), logoWidget]
          : [logoWidget, const SizedBox(width: 4), nameText],
    );
  }
}

class _CommentatorChip extends StatelessWidget {
  const _CommentatorChip({required this.name, required this.avatar});

  final String name;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (avatar.isNotEmpty) ...[
            CircleAvatar(
              radius: 7,
              backgroundColor: Colors.white24,
              backgroundImage: NetworkImage(avatar),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            name,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

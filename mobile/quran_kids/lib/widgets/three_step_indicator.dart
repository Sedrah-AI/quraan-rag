import 'package:flutter/material.dart';

/// Where a step stands relative to the child's current position in the
/// Teacher -> Friend -> Me loop.
enum LoopStepState { upcoming, active, completed }

const teacherStepColor = Color(0xFF2D6A4F);
const friendStepColor = Color(0xFFE8A33D);
const meStepColor = Color(0xFFE0577A);

/// The 3-step loop (Teacher recites, Friend recites, Me/child recites)
/// rendered as three tappable avatars joined by connector lines - doubles
/// as both a progress indicator (dim/highlight shows where the child is)
/// and a way to replay an earlier step (tap Teacher/Friend any time
/// they're not mid-playback).
class ThreeStepIndicator extends StatelessWidget {
  final LoopStepState teacher;
  final LoopStepState friend;
  final LoopStepState me;
  final VoidCallback? onTapTeacher;
  final VoidCallback? onTapFriend;
  final VoidCallback? onTapMe;

  const ThreeStepIndicator({
    super.key,
    required this.teacher,
    required this.friend,
    required this.me,
    this.onTapTeacher,
    this.onTapFriend,
    this.onTapMe,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepAvatar(
          state: teacher,
          color: teacherStepColor,
          icon: Icons.record_voice_over,
          label: 'Teacher',
          onTap: onTapTeacher,
        ),
        _Connector(lit: teacher == LoopStepState.completed),
        _StepAvatar(
          state: friend,
          color: friendStepColor,
          icon: Icons.emoji_people,
          label: 'Friend',
          onTap: onTapFriend,
        ),
        _Connector(lit: friend == LoopStepState.completed),
        _StepAvatar(
          state: me,
          color: meStepColor,
          icon: Icons.mic,
          label: 'Me',
          onTap: onTapMe,
        ),
      ],
    );
  }
}

class _StepAvatar extends StatelessWidget {
  final LoopStepState state;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _StepAvatar({
    required this.state,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = state == LoopStepState.active;
    final isCompleted = state == LoopStepState.completed;
    final filled = isActive || isCompleted;
    final size = isActive ? 64.0 : 52.0;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : Colors.grey.shade200,
              boxShadow: isActive
                  ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16, spreadRadius: 2)]
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    icon,
                    size: isActive ? 32 : 26,
                    color: filled ? Colors.white : Colors.grey.shade500,
                  ),
                ),
                if (isCompleted)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.check_circle, size: 16, color: color),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: filled ? color : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  final bool lit;

  const _Connector({required this.lit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 3,
      margin: const EdgeInsets.only(bottom: 20),
      color: lit ? Colors.green.shade300 : Colors.grey.shade300,
    );
  }
}

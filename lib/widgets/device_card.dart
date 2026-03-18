import 'package:flutter/material.dart';
import '../models/valve_device.dart';
import '../utils/constants.dart';

class DeviceCard extends StatelessWidget {
  final ValveDevice device;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  const DeviceCard({super.key, required this.device, this.onTap, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppDimensions.paddingMedium),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadius)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _getStatusColor().withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_getStatusIcon(), color: _getStatusColor(), size: 28),
                  ),
                  const SizedBox(width: AppDimensions.paddingMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: device.isConnected ? AppColors.success : AppColors.offline)),
                          const SizedBox(width: 6),
                          Text(device.isConnected ? 'Connected' : 'Offline', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ]),
                      ],
                    ),
                  ),
                  if (device.isConnected) _buildToggleButton(),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: device.position / 100, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()), minHeight: 8),
              ),
              const SizedBox(height: AppDimensions.paddingSmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: _getStatusColor().withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text('${device.status.displayName} (${device.position}%)', style: TextStyle(fontSize: 12, color: _getStatusColor(), fontWeight: FontWeight.w500)),
                  ),
                  if (device.lastUpdated != null) Text(_formatLastUpdated(), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    final isOpen = device.status == ValveStatus.open;
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: isOpen ? AppColors.error : AppColors.success, borderRadius: BorderRadius.circular(20)),
        child: Text(isOpen ? 'CLOSE' : 'OPEN', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Color _getStatusColor() {
    switch (device.status) {
      case ValveStatus.open: return AppColors.success;
      case ValveStatus.closed: return AppColors.error;
      case ValveStatus.partial: return AppColors.warning;
      case ValveStatus.offline: return AppColors.offline;
      case ValveStatus.error: return AppColors.error;
    }
  }

  IconData _getStatusIcon() {
    switch (device.status) {
      case ValveStatus.open: return Icons.check_circle;
      case ValveStatus.closed: return Icons.cancel;
      case ValveStatus.partial: return Icons.timelapse;
      case ValveStatus.offline: return Icons.cloud_off;
      case ValveStatus.error: return Icons.error;
    }
  }

  String _formatLastUpdated() {
    if (device.lastUpdated == null) return '';
    final diff = DateTime.now().difference(device.lastUpdated!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

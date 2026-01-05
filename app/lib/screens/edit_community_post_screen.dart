import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/communitypost_service.dart';

class EditCommunityPostScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const EditCommunityPostScreen({super.key, required this.post});

  @override
  State<EditCommunityPostScreen> createState() => _EditCommunityPostScreenState();
}

class _EditCommunityPostScreenState extends State<EditCommunityPostScreen> {
  final _contentController = TextEditingController();
  final _communityService = CommunityService();
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();

  List<String> _existingImageUrls = [];
  List<File> _newImages = [];
  List<int> _imagesToDelete = [];
  bool _isUpdating = false;
  bool _hasAudio = false;
  bool _removeAudio = false;
  int? _audioDuration;
  
  File? _newAudioFile;
  int? _newAudioDuration;
  bool _isRecording = false;
  bool _isPlayingAudio = false;
  Duration _recordDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _contentController.text = widget.post['content'] ?? '';
    
    final images = widget.post['images'] as List? ?? [];
    _existingImageUrls = images
        .map((img) => img['image_url'] as String)
        .toList();
    
    final audioUrl = widget.post['audio_url'] as String?;
    final audioDuration = widget.post['duration'] as int?;
    _hasAudio = audioUrl != null && audioUrl.isNotEmpty && (audioDuration ?? 0) > 0;
    _audioDuration = audioDuration;
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlayingAudio = state == PlayerState.playing;
      });
    });
    
    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _playbackPosition = position;
      });
    });
    
    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _playbackDuration = duration;
      });
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final totalImages = (_existingImageUrls.length - _imagesToDelete.length) + _newImages.length;
    
    if (totalImages >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 5 images allowed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final List<XFile> images = await _picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (images.length + totalImages > 5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 5 images allowed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _newImages.addAll(images.map((x) => File(x.path)));
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _imagesToDelete.add(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  void _toggleRemoveAudio() {
    setState(() {
      _removeAudio = !_removeAudio;
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        setState(() {
          _isRecording = true;
          _recordDuration = Duration.zero;
        });

        while (_isRecording) {
          await Future.delayed(const Duration(seconds: 1));
          if (_isRecording) {
            setState(() {
              _recordDuration = Duration(seconds: _recordDuration.inSeconds + 1);
            });

            if (_recordDuration.inSeconds >= 60) {
              await _stopRecording();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Maximum recording time of 60 seconds reached'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      
      setState(() {
        _isRecording = false;
        if (path != null) {
          _newAudioFile = File(path);
          _newAudioDuration = _recordDuration.inSeconds;
          _removeAudio = false; 
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error stopping recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleAudioPlayback() async {
    if (_newAudioFile == null) return;

    if (_isPlayingAudio) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(_newAudioFile!.path));
    }
  }

  void _removeNewAudio() {
    setState(() {
      _newAudioFile = null;
      _newAudioDuration = null;
      _recordDuration = Duration.zero;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
    });
    _audioPlayer.stop();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _updatePost() async {
    final content = _contentController.text.trim();

    if (content.isEmpty && 
        _existingImageUrls.length == _imagesToDelete.length && 
        _newImages.isEmpty && 
        (_hasAudio && _removeAudio) &&
        _newAudioFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final result = await _communityService.updateCommunityPost(
        widget.post['id'],
        content,
        imagesToDelete: _imagesToDelete,
        newImages: _newImages.isNotEmpty ? _newImages : null,
        removeAudio: _removeAudio,
        newAudioFile: _newAudioFile,
        newAudioDuration: _newAudioDuration,
      );

      if (result != null && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post updated successfully!'),
            backgroundColor: Color(0xFF7C3AED),
          ),
        );
      } else {
        throw Exception('Failed to update post');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating post: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleExistingImages = _existingImageUrls
        .asMap()
        .entries
        .where((entry) => !_imagesToDelete.contains(entry.key))
        .map((entry) => {'index': entry.key, 'url': entry.value})
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Edit Post'),
        actions: [
          TextButton(
            onPressed: _isUpdating ? null : _updatePost,
            child: _isUpdating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _contentController,
              style: const TextStyle(color: Colors.white),
              maxLines: 6,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 24),

            if (_hasAudio && !_removeAudio && _newAudioFile == null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.audiotrack, color: Color(0xFF7C3AED)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Existing Audio Recording',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Duration: ${_audioDuration ?? 0}s',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _toggleRemoveAudio,
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Remove', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),

            if (_hasAudio && _removeAudio && _newAudioFile == null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.red),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Audio will be removed',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: _toggleRemoveAudio,
                      child: const Text('Undo', style: TextStyle(color: Color(0xFF7C3AED))),
                    ),
                  ],
                ),
              ),

            if ((!_hasAudio || _removeAudio || _newAudioFile != null) && !_isRecording)
              ElevatedButton.icon(
                onPressed: _isUpdating || _newAudioFile != null
                    ? null
                    : _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('Record Audio'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            if (_isRecording)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.red),
                        const SizedBox(width: 12),
                        Text(
                          'Recording: ${_formatDuration(_recordDuration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Recording'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

            if (_newAudioFile != null && !_isRecording)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF7C3AED),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.audiotrack,
                          color: Color(0xFF7C3AED),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'New Audio Recording',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _removeNewAudio,
                          icon: const Icon(Icons.close, color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _toggleAudioPlayback,
                          icon: Icon(
                            _isPlayingAudio ? Icons.pause : Icons.play_arrow,
                            color: const Color(0xFF7C3AED),
                            size: 32,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: _playbackPosition.inSeconds.toDouble(),
                                  max: (_playbackDuration.inSeconds > 0
                                          ? _playbackDuration.inSeconds
                                          : 1)
                                      .toDouble(),
                                  onChanged: (value) async {
                                    await _audioPlayer.seek(
                                      Duration(seconds: value.toInt()),
                                    );
                                  },
                                  activeColor: const Color(0xFF7C3AED),
                                  inactiveColor: Colors.white24,
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_playbackPosition),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(Duration(
                                      seconds: _newAudioDuration ?? 0,
                                    )),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            const Text(
              'Images',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _isUpdating ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add Images'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (visibleExistingImages.isNotEmpty || _newImages.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: visibleExistingImages.length + _newImages.length,
                itemBuilder: (context, index) {
                  if (index < visibleExistingImages.length) {
                    final imageData = visibleExistingImages[index];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageData['url']?.toString() ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.error);
                            },
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              final index = imageData['index'];
                              if (index is int) {
                                _removeExistingImage(index);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Existing',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    final newImageIndex = index - visibleExistingImages.length;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _newImages[newImageIndex],
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeNewImage(newImageIndex),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'New',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
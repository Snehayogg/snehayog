import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/agent/data/autonomous_agent_service.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/features/auth/data/usermodel.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/shared/widgets/vayu_logo.dart';

// Simple model for chat messages
class AgentMessage {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? data; // For structured agent results
  final bool isLoading;
  final String? loadingStep; // "Thinking...", "Drafting..."

  AgentMessage({
    required this.text,
    required this.isUser,
    this.data,
    this.isLoading = false,
    this.loadingStep,
  });
}

class AgentScreen extends StatefulWidget {
  const AgentScreen({Key? key}) : super(key: key);

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final TextEditingController _intentController = TextEditingController();
  final AutonomousAgentService _agentService = AutonomousAgentService();
  final ScrollController _scrollController = ScrollController();
  
  final List<AgentMessage> _messages = [];
  bool _isInputEnabled = true;

  @override
  void dispose() {
    _intentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _generateContent() async {
    final intent = _intentController.text.trim();
    if (intent.isEmpty) return;

    final userProvider = Provider.of<GoogleSignInController>(context, listen: false);
    final user = userProvider.userData != null 
        ? UserModel.fromJson(userProvider.userData!) 
        : null;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to use the agent.')),
      );
      return;
    }

    // 1. Add User Message immediately
    setState(() {
      _messages.add(AgentMessage(text: intent, isUser: true));
      _intentController.clear();
      _isInputEnabled = false;
      
      // 2. Add Loading Message
      _messages.add(AgentMessage(
        text: '', 
        isUser: false, 
        isLoading: true, 
        loadingStep: 'Analyzing Request...'
      ));
    });
    _scrollToBottom();

    // UX Simulation steps
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
       setState(() {
          // Update the last message (loading state)
          _messages.last = AgentMessage(
            text: '', isUser: false, isLoading: true, loadingStep: 'Thinking & Planning...'
          );
       });
    }
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
       setState(() {
          _messages.last = AgentMessage(
            text: '', isUser: false, isLoading: true, loadingStep: 'Drafting Content...'
          );
       });
    }

    // Fetch Videos Context
    List<String> videoTitles = [];
    try {
      final videoService = VideoService();
      final videos = await videoService.getUserVideos(user.id, page: 1, limit: 5);
      videoTitles = videos.map((v) => v.videoName).toList();
    } catch (e) {
      // Ignore error
    }

    try {
      final result = await _agentService.generateContent(
        user: user,
        intent: intent,
        videoTitles: videoTitles,
      );

      if (mounted) {
        setState(() {
          _isInputEnabled = true;
           // Remove loading message
          _messages.removeLast();

          if (result != null && result['status'] == 'success') {
            // Add Result Message
            _messages.add(AgentMessage(
              text: 'Here is what I drafted for you based on "${intent}"', // Optional text
              isUser: false,
              data: result['data'],
            ));
          } else {
             _messages.add(AgentMessage(
              text: 'Sorry, I failed to generate content. Please try again.',
              isUser: false,
            ));
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInputEnabled = true;
          _messages.removeLast(); // Remove loading
          _messages.add(AgentMessage(
            text: 'Error occurred: $e',
            isUser: false,
          ));
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Agent',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty 
              ? _buildWelcomeMessage()
              : _buildMessagesList(),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(AgentMessage msg) {
    if (msg.isUser) {
      // USER BUBBLE (Right)
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
    } else {
      // AGENT BUBBLE (Left)
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 24, right: 20), // More margin for agent results
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar/Icon
              Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                       color: AppTheme.primary.withOpacity(0.2),
                       shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, size: 16, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 8),
                  const Text('Vayu Agent', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              
              if (msg.isLoading)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                       const SizedBox(width: 12),
                       Text(msg.loadingStep ?? 'Thinking...', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              else if (msg.data != null)
                 _buildResultCard(msg.data!)
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(msg.text, style: const TextStyle(color: Colors.white)),
                ),
            ],
          ),
        ),
      );
    }
  }

  // Extracted Result Card Logic
  Widget _buildResultCard(Map<String, dynamic> data) {
    final title = data['title'] ?? 'No Title';
    final caption = data['caption'] ?? 'No Caption';
    final hashtags = data['hashtags'] ?? '';
    final imagePrompt = data['imagePrompt'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Generated Draft', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
              // Copy/Action Icons could go here
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(caption, style: const TextStyle(color: Colors.white70, height: 1.5)),
          const SizedBox(height: 12),
          Container(
             padding: const EdgeInsets.all(8),
             decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
             child: Text(hashtags, style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          
          if (imagePrompt.isNotEmpty) ...[
             const SizedBox(height: 16),
             const Divider(color: Colors.white10),
             const SizedBox(height: 8),
             const Text('VISUAL PROMPT', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
             const SizedBox(height: 4),
             Text(imagePrompt, style: const TextStyle(color: Colors.purpleAccent, fontSize: 13, height: 1.3)),
          ],
        ],
      ),
    );
  }

  Widget _buildWelcomeMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const VayuLogo(fontSize: 48),
          const SizedBox(height: 24),
          const Text(
            'Ready to Create?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                enabled: _isInputEnabled,
                controller: _intentController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Ask Vayu...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                  isDense: true,
                ),
                maxLines: 5,
                minLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: !_isInputEnabled 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              onPressed: _isInputEnabled ? _generateContent : null,
              style: IconButton.styleFrom(
                 backgroundColor: _isInputEnabled ? AppTheme.primary : Colors.grey,
                 padding: const EdgeInsets.all(8),
                 minimumSize: const Size(36, 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

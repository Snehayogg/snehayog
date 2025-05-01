import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _searchResults = [
        {
          'type': 'user',
          'name': 'John Doe',
          'avatar': 'https://example.com/avatar1.jpg',
        },
        {
          'type': 'video',
          'caption': 'Funny Cat',
          'thumbnail': 'https://example.com/thumb1.jpg',
        },
        {
          'type': 'user',
          'name': 'Jane Smith',
          'avatar': 'https://example.com/avatar2.jpg',
        },
        {
          'type': 'video',
          'caption': 'Amazing Yoga',
          'thumbnail': 'https://example.com/thumb2.jpg',
        },
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002B36), // Solarized Dark Base
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF073642), // Solarized Dark Content
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _performSearch(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search users or videos...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF268BD2),
                    ), // Solarized Blue
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: Color(0xFF586E75),
                      ), // Solarized Base1
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchResults = []);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child:
                  _isLoading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF268BD2), // Solarized Blue
                        ),
                      )
                      : _searchResults.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 80,
                              color: const Color(
                                0xFF586E75,
                              ).withOpacity(0.5), // Solarized Base1
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No results found',
                              style: TextStyle(
                                color: Color(0xFF586E75), // Solarized Base1
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF073642,
                              ), // Solarized Dark Content
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(
                                  0xFF268BD2,
                                ), // Solarized Blue
                                child:
                                    item['type'] == 'user'
                                        ? const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                        )
                                        : const Icon(
                                          Icons.videocam,
                                          color: Colors.white,
                                        ),
                              ),
                              title: Text(
                                item['name'] ?? item['caption'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                item['type'] == 'user' ? 'User' : 'Video',
                                style: const TextStyle(
                                  color: Color(0xFF586E75), // Solarized Base1
                                ),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                color: Color(
                                  0xFF268BD2,
                                ), // Solarized Blue
                                size: 16,
                              ),
                              onTap: () {
                                // Handle item tap
                              },
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

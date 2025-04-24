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
    // Silence the warning by using the query variable
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    // Replace with your actual API call
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _searchResults = [
        {'type': 'user', 'name': 'John Doe'},
        {'type': 'video', 'caption': 'Funny Cat'},
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _performSearch(),
              decoration: InputDecoration(
                hintText: 'Search users or videos',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _performSearch,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        if (item['type'] == 'user') {
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(item['name']),
                          );
                        } else {
                          return ListTile(
                            leading: const Icon(Icons.videocam),
                            title: Text(item['caption']),
                          );
                        }
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

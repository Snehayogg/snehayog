import 'package:snehayog/services/comments/comments_data_source.dart';
import 'package:snehayog/services/ad_comment_service.dart';

class AdCommentsDataSource implements CommentsDataSource {
  final String adId;
  final AdCommentService adCommentService;

  AdCommentsDataSource({required this.adId, required this.adCommentService});

  @override
  String get targetId => adId;

  @override
  String get targetType => 'ad';

  @override
  Future<(List<Map<String, dynamic>>, bool)> fetchComments(
      {int page = 1, int limit = 20}) async {
    final resp = await adCommentService.getAdComments(
        adId: adId, page: page, limit: limit);
    final comments = List<Map<String, dynamic>>.from(resp['comments'] ?? []);
    final hasNext = (resp['pagination']?['hasNextPage'] ?? false) as bool;
    return (comments, hasNext);
  }

  @override
  Future<Map<String, dynamic>> postComment({required String content}) async {
    final created =
        await adCommentService.addAdComment(adId: adId, content: content);
    return Map<String, dynamic>.from(created['comment'] ?? {});
  }

  @override
  Future<void> deleteComment({required String commentId}) async {
    await adCommentService.deleteAdComment(adId: adId, commentId: commentId);
  }

  @override
  Future<Map<String, dynamic>> toggleLikeOnComment(
      {required String commentId}) async {
    final updated =
        await adCommentService.likeAdComment(adId: adId, commentId: commentId);
    return Map<String, dynamic>.from(updated['comment'] ?? {});
  }

  @override
  Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    return raw;
  }
}

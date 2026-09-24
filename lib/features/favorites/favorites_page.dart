import '../history/records_page.dart';

// 收藏入口复用历史列表和同一份本地记录。
class FavoritesPage extends RecordsPage {
  const FavoritesPage({super.key}) : super(favoritesOnly: true);
}

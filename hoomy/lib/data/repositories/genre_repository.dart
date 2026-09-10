import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 风格取数：曲库里的流派分组。
class GenreRepository {
  GenreRepository(this._client);

  final SubsonicClient _client;

  Future<List<SubsonicGenre>> getGenres() => _client.getGenres();
}

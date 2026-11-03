/// Estados de sincronização de um registro guardado no SQLite.
///
/// - [synced]: o registro local é igual ao que está no Firestore.
/// - [pending]: criado/alterado localmente e ainda não enviado à nuvem.
/// - [pendingDelete]: exclusão definitiva feita localmente, ainda não
///   replicada no Firestore (o registro fica oculto até a nuvem confirmar).
class SyncStatus {
  SyncStatus._();

  static const int synced = 0;
  static const int pending = 1;
  static const int pendingDelete = 2;
}

# Bloco de Notas

Aplicativo de notas feito em Flutter que guarda tudo no aparelho (SQLite) e mantém uma cópia na nuvem (Cloud Firestore) ligada à conta de cada usuário. O objetivo desta versão é evoluir o bloco de notas da turma com sincronização entre banco local e Firebase, categorias, pesquisa e uma funcionalidade extra de organização (lixeira com recuperação, arquivamento e ordenação), seguindo o fluxo de fork, branch e Pull Request no GitHub.

## Funcionalidades

O usuário cria uma conta com e-mail e senha, entra no aplicativo e permanece logado nas próximas aberturas. Cada nota pode ser criada, consultada, editada e excluída, e todas essas operações acontecem tanto no SQLite quanto no Firebase. As notas pertencem ao usuário autenticado: ao entrar de novo ou em outro aparelho, a sincronização traz de volta as notas guardadas na nuvem.

As notas podem ser organizadas em categorias. O app já cria "Estudos", "Trabalho" e "Pessoal" no primeiro acesso, e o usuário cria outras direto na tela da nota pelo botão "Nova categoria". Na tela principal, as categorias aparecem como filtros; pressionar e segurar uma categoria permite excluí-la (as notas dela ficam sem categoria). A caixa de pesquisa localiza notas pelo título ou pelo conteúdo, sem diferenciar maiúsculas de minúsculas nem acentos, e a pesquisa combina com o filtro de categoria.

Como funcionalidade adicional foram implementadas três, todas com a operação real por trás da interface. A lixeira com recuperação: "Mover para a lixeira" é uma exclusão temporária, a nota pode ser restaurada e só some de vez em "Excluir definitivamente" (que apaga também no Firebase). O arquivamento: notas arquivadas saem da lista principal sem serem excluídas e podem ser desarquivadas. A ordenação: a lista pode ser ordenada por data de criação ou por última atualização, da mais recente para a mais antiga ou o contrário.

## Tecnologias e dependências

O projeto usa Flutter e Dart (SDK conforme o `pubspec.yaml`), com os pacotes `firebase_core`, `firebase_auth` e `cloud_firestore` para a parte de nuvem, `sqflite` e `path` para o banco local, e `flutter_lints` para a análise estática. Funciona em Android e iOS; o `sqflite` não tem suporte a Web, então a pasta `web/` não deve ser usada para executar o app.

## Como instalar e executar

Instale o Flutter e confira o ambiente com `flutter doctor`. Depois, na pasta do projeto:

```bash
flutter pub get
flutter run
```

Para rodar os testes unitários: `flutter test`. Se o `pub get` reclamar de versão incompatível do `cloud_firestore`, rode `flutter pub add cloud_firestore` para que o Flutter escolha a versão compatível com o `firebase_core` do projeto. Se o Android reclamar de `minSdk`, defina `minSdk = 23` (ou superior) em `android/app/build.gradle.kts`.

## Como configurar o Firebase

O repositório da professora já traz `lib/firebase_options.dart` e `android/app/google-services.json` apontando para o projeto Firebase da turma. Esses arquivos contêm apenas identificadores públicos do app (não são senhas nem chaves privadas), mas, para rodar com o seu próprio projeto e poder publicar as regras de segurança, crie um projeto seu e gere os arquivos novamente:

1. No [console do Firebase](https://console.firebase.google.com), crie um projeto.
2. Em Authentication, ative o provedor "E-mail/senha".
3. Em Firestore Database, crie o banco (modo produção).
4. Instale as ferramentas e gere a configuração do app:
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   O `flutterfire configure` recria `lib/firebase_options.dart` e `android/app/google-services.json` para o seu projeto.
5. Publique as regras de segurança deste repositório (`firestore.rules`):
   ```bash
   firebase deploy --only firestore:rules
   ```
   Se preferir, copie o conteúdo de `firestore.rules` para Firestore Database > Regras no console e clique em Publicar.

Nenhuma senha ou chave privada (por exemplo, contas de serviço) deve ser adicionada ao repositório.

## Arquitetura e organização dos arquivos

O código segue uma separação simples em camadas: telas e widgets cuidam só da interface, o repositório concentra as regras de negócio e de sincronização, e duas fontes de dados (SQLite e Firestore) fazem apenas o acesso aos dados.

```
lib/
  main.dart                       Inicialização, tema e AuthGate (login x notas)
  firebase_options.dart           Gerado pelo flutterfire configure
  models/
    note.dart                     Nota + enums NoteView e NoteSort
    category.dart                 Categoria
    sync_status.dart              synced / pending / pendingDelete
  database/
    database_helper.dart          SQLite: tabelas notes, categories e meta
  services/
    auth_service.dart             Login, cadastro, logout e mensagens de erro
    firestore_service.dart        Fonte de dados remota (Cloud Firestore)
  repositories/
    notes_repository.dart         Local primeiro + sincronização + SyncState
  pages/
    login_page.dart, register_page.dart
    notes_page.dart               Lista, pesquisa, categorias, lixeira, arquivadas
    note_form_page.dart           Criar/editar nota e escolher/criar categoria
  widgets/
    note_card.dart                Cartão da nota com menu de ações
  utils/
    text_utils.dart               Normalização de texto (pesquisa) e formatação de data
firestore.rules                   Regras de segurança do Firestore
test/widget_test.dart             Testes unitários de modelos e utilitários
```

## Padrões de projeto adotados

O **Repository** (`NotesRepository`) é o padrão central: as telas nunca falam diretamente com o SQLite nem com o Firestore, elas pedem notas e categorias ao repositório, que decide onde gravar, quando enviar para a nuvem e como resolver conflitos. Assim a interface não precisa saber que existem dois armazenamentos.

O **Singleton** aparece em `DatabaseHelper.instance` e `NotesRepository.instance`, para que o app inteiro use uma única conexão com o banco e um único estado de sincronização. Os métodos **Factory** `Note.fromMap`, `Note.fromFirestore` (e os equivalentes em `Category`) isolam a conversão entre os formatos de cada armazenamento e o objeto do app; `toMap` e `toFirestore` fazem o caminho inverso, e é por isso que `syncStatus` existe só no SQLite.

O **Observer** é usado em dois pontos: o `SyncState` do repositório é um `ValueNotifier` observado pela tela de notas com `ValueListenableBuilder` (é o que atualiza a faixa "Sincronizando / Sem conexão"), e o `AuthGate` observa `FirebaseAuth.authStateChanges()` para trocar entre login e notas quando o usuário entra ou sai. Por fim, a separação entre `DatabaseHelper` (SQL) e `FirestoreService` (nuvem) segue a ideia de **fonte de dados** (data source), o que permitiu testar os modelos sem depender de Firebase.

## Armazenamento local e integração com o Firebase

No aparelho, o SQLite (`bloco_notas.db`) tem três tabelas. `notes` guarda id, uid do usuário, título, conteúdo, categoria, datas de criação e atualização, se está arquivada, a data de exclusão temporária (quando está na lixeira) e o `sync_status`. `categories` guarda as categorias com o mesmo controle de sincronização, e `meta` registra, por usuário, se as categorias iniciais já foram criadas.

Na nuvem, os dados ficam em `users/{uid}/notes/{noteId}` e `users/{uid}/categories/{categoryId}`. O id de cada nota é gerado pelo próprio Firestore (sem usar a rede) e é o mesmo no SQLite e na nuvem, o que permite reconhecer o mesmo registro nos dois lados. As datas são guardadas como milissegundos.

A pesquisa roda sobre o SQLite: o repositório carrega as notas da visão atual, já filtradas por categoria, e compara o texto normalizado (minúsculas e sem acento) com o título e o conteúdo. Como o banco local é mantido igual ao Firebase pela sincronização, a pesquisa funciona mesmo sem internet e reflete as notas recuperadas da nuvem.

## Estratégia de sincronização e tratamento de erros

O app trabalha com "local primeiro". Toda criação, edição, arquivamento, envio para a lixeira ou exclusão é gravada imediatamente no SQLite com `sync_status = pending` e, em seguida, o repositório tenta enviar aquela nota ao Firestore em segundo plano; se o envio funciona, a nota passa para `synced`. Se falhar, ela continua `pending` e o cartão da nota mostra um ícone de nuvem cortada. Exclusões definitivas usam o estado `pendingDelete`: a nota some da tela na hora, mas a linha só é apagada do SQLite depois que o Firestore confirma a exclusão.

A sincronização completa (`NotesRepository.sync`) roda ao abrir a tela de notas, ao voltar para o app e quando o usuário toca no botão de sincronizar. Ela busca tudo da nuvem e então aplica quatro passos: executa as exclusões definitivas pendentes; traz para o aparelho as notas novas ou mais recentes da nuvem; envia as notas pendentes que não perderam para a versão da nuvem; e remove localmente as notas já sincronizadas que não existem mais na nuvem (excluídas em outro aparelho). Em caso de conflito, vence a alteração com `updatedAt` mais recente (last-write-wins). Uma nota só é marcada como sincronizada se não foi editada enquanto o envio estava em andamento.

Para tratar falhas de conexão, todas as chamadas ao Firestore têm timeout de 10 segundos, e a leitura usa `Source.server`. Isso é necessário porque, sem internet, o Firestore não devolve erro, ele apenas espera a conexão voltar. O cache offline próprio do Firestore foi desativado em `main.dart` para que exista uma única fila de pendências, a do SQLite. Quando algo falha, o app não perde dados nem trava: o `SyncState` muda para `offline`, a tela mostra um aviso de que as alterações estão salvas no aparelho e serão enviadas depois, e a próxima sincronização tenta de novo. Erros de login e cadastro são traduzidos para mensagens em português. O login em si exige internet, mas quem já está logado continua usando o app offline.

## Autenticação e segurança dos dados

A autenticação é feita com Firebase Auth (e-mail e senha). O `AuthGate` mostra a tela de login quando não há sessão e a tela de notas quando há, e o `uid` do usuário autenticado é usado em todas as consultas locais (`WHERE uid = ?`) e no caminho dos documentos na nuvem, de modo que dois usuários no mesmo aparelho não enxergam as notas um do outro.

A segurança na nuvem é garantida pelas regras do arquivo `firestore.rules`: só é permitido ler, criar, alterar ou excluir documentos em `users/{userId}/...` quando `request.auth.uid == userId`, o campo `uid` do documento precisa ser igual ao do usuário, título, conteúdo e nome de categoria são validados (tipo e tamanho), e qualquer outro caminho é negado. Na prática, um usuário não consegue ler nem alterar as notas de outro mesmo conhecendo o caminho.

## Capturas de tela

As imagens ficam em `docs/screenshots/`.

| Evidência | Arquivo |
| --- | --- |
| Tela de login | `docs/screenshots/login.png` |
| Lista de notas com categorias e pesquisa | `docs/screenshots/lista-notas.png` |
| Criação de nota com categoria | `docs/screenshots/nova-nota.png` |
| Resultado de pesquisa | `docs/screenshots/pesquisa.png` |
| Lixeira e arquivadas | `docs/screenshots/lixeira.png` |
| Aviso de falta de conexão | `docs/screenshots/offline.png` |
| Notas no Firestore (console do Firebase) | `docs/screenshots/firestore-notas.png` |
| Categorias no Firestore | `docs/screenshots/firestore-categorias.png` |
| Regras de segurança publicadas | `docs/screenshots/firestore-regras.png` |

![Notas no Firestore](docs/screenshots/firestore-notas.png)

## Resumo do que foi alterado (Pull Request)

Em relação ao projeto base, foram criados `models/category.dart`, `models/sync_status.dart`, `repositories/notes_repository.dart`, `services/firestore_service.dart`, `utils/text_utils.dart` e `firestore.rules`. Foram reescritos `models/note.dart` (id em texto compartilhado com a nuvem, datas em milissegundos, categoria, arquivamento, lixeira e status de sincronização), `database/database_helper.dart` (novo esquema; o `CREATE TABLE` anterior tinha uma vírgula sobrando que impedia a criação da tabela), `pages/notes_page.dart`, `pages/note_form_page.dart`, `widgets/note_card.dart` e `main.dart` (inicialização do Firestore e `AuthGate`). Foram ajustados `services/auth_service.dart` e as telas de login e cadastro (mensagens de erro e navegação pelo `AuthGate`), `pubspec.yaml` (dependência `cloud_firestore`), `firebase.json` (regras do Firestore), `AndroidManifest.xml` (permissão de internet, necessária em builds de release) e `test/widget_test.dart` (o teste de contador padrão foi substituído por testes unitários reais).

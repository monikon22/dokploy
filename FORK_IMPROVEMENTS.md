# Dokploy Fork Improvements

Этот форк Dokploy включает следующие улучшения:

## 1. GitHub Packages Support

### Изменения в `.github/workflows/deploy.yml`:
- Переключение с Docker Hub на GitHub Container Registry (ghcr.io)
- Автоматическая аутентификация через GITHUB_TOKEN
- Обновлённые теги для образов

### Изменения в `install.sh`:
- Поддержка установки из GitHub Packages
- Новые параметры командной строки:
  - `--github-packages` - использовать GitHub Packages
  - `--registry URL` - использовать кастомный реестр
  - `--tag TAG` - указать тег образа
- Автоматическая аутентификация в GitHub Container Registry

### Использование:

```bash
# Установка из GitHub Packages
curl -sSL https://raw.githubusercontent.com/username/dokploy/main/install.sh | bash -s -- --github-packages

# Установка с кастомным реестром
curl -sSL https://raw.githubusercontent.com/username/dokploy/main/install.sh | bash -s -- --registry ghcr.io/username/dokploy-server --tag latest

# Установка с GitHub Token для приватных репозиториев
export GITHUB_TOKEN=your_github_token
curl -sSL https://raw.githubusercontent.com/username/dokploy/main/install.sh | bash -s -- --github-packages
```

## 2. Новые права пользователей

### Добавлены два новых права:

1. **Access to Service Environments** - ограничивает доступ к вкладке "Environment" на страницах сервисов
2. **Access to Service Terminal** - ограничивает доступ к кнопке "Open Terminal" на страницах сервисов

### Схема базы данных:

Добавлены новые столбцы в таблицу `member`:
- `canAccessToServiceEnvironments` BOOLEAN NOT NULL DEFAULT false
- `canAccessToServiceTerminal` BOOLEAN NOT NULL DEFAULT false

### Пользовательский интерфейс:

- Добавлены переключатели в форме управления правами пользователей
- Условное отображение вкладки Environment
- Условное отображение кнопки Terminal

### Файлы, которые были изменены:

#### Схема базы данных:
- `packages/server/src/db/schema/account.ts`
- `packages/server/src/db/schema/user.ts`

#### UI компоненты:
- `apps/dokploy/components/dashboard/settings/users/add-permissions.tsx`
- `apps/dokploy/components/dashboard/application/general/show.tsx`
- `apps/dokploy/components/dashboard/compose/general/actions.tsx`
- `apps/dokploy/components/dashboard/postgres/general/show-general-postgres.tsx`

#### Страницы сервисов:
- `apps/dokploy/pages/dashboard/project/[projectId]/environment/[environmentId]/services/application/[applicationId].tsx`
- `apps/dokploy/pages/dashboard/project/[projectId]/environment/[environmentId]/services/compose/[composeId].tsx`

## 3. Миграция базы данных

Выполните следующий SQL для добавления новых прав:

```sql
ALTER TABLE member 
ADD COLUMN IF NOT EXISTS "canAccessToServiceEnvironments" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "canAccessToServiceTerminal" BOOLEAN NOT NULL DEFAULT false;
```

## 4. Логика работы прав

### Access to Service Environments:
- Если у пользователя роль `owner` - доступ разрешён
- Если у пользователя установлено право `canAccessToServiceEnvironments` - доступ разрешён
- Иначе - вкладка Environment скрыта

### Access to Service Terminal:
- Если у пользователя роль `owner` - доступ разрешён
- Если у пользователя установлено право `canAccessToServiceTerminal` - доступ разрешён
- Иначе - кнопка "Open Terminal" скрыта

## 5. Дополнительные изменения

Для полной реализации необходимо применить аналогичные изменения к остальным типам сервисов:
- MySQL (`apps/dokploy/components/dashboard/mysql/general/show-general-mysql.tsx`)
- Redis (`apps/dokploy/components/dashboard/redis/general/show-general-redis.tsx`)
- MongoDB (`apps/dokploy/components/dashboard/mongo/general/show-general-mongo.tsx`)
- MariaDB (`apps/dokploy/components/dashboard/mariadb/general/show-general-mariadb.tsx`)

И их соответствующие страницы в:
- `apps/dokploy/pages/dashboard/project/[projectId]/environment/[environmentId]/services/`

## Заметки по разработке

- Все изменения совместимы с существующей архитектурой Dokploy
- Права по умолчанию отключены для обеспечения безопасности
- Административные пользователи (role="owner") имеют доступ ко всем функциям
- Интерфейс автоматически адаптируется под права пользователя
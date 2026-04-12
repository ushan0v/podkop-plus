# Podkop Plus

Форк [itdoginfo/podkop](https://github.com/itdoginfo/podkop)

Основная суть форка — улучшение LuCI-интерфейса и полный переход на rule-based модель маршрутизации, что делает управление правилами более гибким и удобным. В качестве дополнительной опции добавлена гибридная интеграция zapret.

<img width="1040" height="600" alt="preview" src="https://github.com/user-attachments/assets/006e737b-e755-4c3c-939d-ca1a828cf11a" />

### Установка

```sh
sh <(wget -O - https://raw.githubusercontent.com/ushan0v/podkop-plus/main/install.sh)
```

### Улучшения и новые возможности

- Улучшенный LuCI-интерефейс секций.
- Переход на rule-based конфигурацию.
- Новое действие `zapret`, которое можно назначать на уровне отдельного правила.
- Мягкое применение настроек без необходимости полной перезагрузки службы.
- В окно просмотра логов добавлена функция автообновления в реальном времени.
- Расширенная настройка частоты обновления списков
  
### Интеграция Zapret

`Zapret` встроен как действие конкретного правила. Под капотом используется [remittor/zapret-openwrt](https://github.com/remittor/zapret-openwrt/releases). Пакет не конфликтует с отдельным полноценным пакетом zapret (luci-app-zapret).

- `sing-box` выбирает и маршрутизирует трафик;
- `zapret` выполняет anti-DPI обработку трафика, который был выбран условием правила.

Для Zapret стратегии NFQWS намеренно запрещены:

- шаблоны и hostlist placeholders: `<HOSTLIST>`, `<HOSTLIST_NOAUTO>`;
- hostname/IP selectors внутри самой стратегии: `--hostlist*`, `--hostlist-auto*`, `--ipset*`;
- ручное управление очередью и fwmark: `--qnum`, `--dpi-desync-fwmark`;
- режимы, которые ломают lifecycle процесса: `--daemon`;
- режимы, которые не должны быть итоговой стратегией запуска: `--dry-run`, `--version`;
- внешние конфиги вида `@file` или `$file`, которые обходят встроенную валидацию и управление очередями.

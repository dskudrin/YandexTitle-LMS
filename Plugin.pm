package Plugins::YandexTitle::Plugin;

use strict;
use warnings;
use utf8;

use Encode qw(decode_utf8);

use Slim::Control::Request;
use Slim::Formats::RemoteMetadata;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Playlist;
use Slim::Plugin::Favorites::OpmlFavorites;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Time::HiRes qw(time);

my $log = logger('server.plugins');
my $prefs = preferences('plugin.yandextitle');

my $previousPlaylistPlay;
my $previousPlaylistIndex;
my $previousPlaylistJump;
my $previousButton;

my %ZONE_BY_PLAYER = (
    'b8:27:eb:6d:75:2c' => 'Z1',
    'b8:27:eb:fa:8f:84' => 'Z2',
    'b8:27:eb:51:c7:73' => 'Z3',
    'b8:27:eb:fb:09:ef' => 'Z4',
    'bb:bb:b0:49:f0:4b' => 'DHC',
);

my %PENDING_BY_PLAYER;
my %PENDING_SOURCE_BY_PLAYER;
my %ACTIVE_SOURCE_BY_PLAYER;
my %IGNORE_NEXT_NEWMETADATA;
my %META_BY_URL;

sub initPlugin {
    my $class = shift;

    $previousPlaylistPlay = Slim::Control::Request::addDispatch(
        [ 'playlist', 'play', '_item', '_title', '_fadein' ],
        [ 1, 0, 0, \&playlistPlay ]
    );

    $previousPlaylistIndex = Slim::Control::Request::addDispatch(
        [ 'playlist', 'index', '_index', '_fadein', '_noplay', '_seekdata' ],
        [ 1, 0, 0, \&playlistIndex ]
    );

    $previousPlaylistJump = Slim::Control::Request::addDispatch(
        [ 'playlist', 'jump', '_index', '_fadein', '_noplay', '_seekdata' ],
        [ 1, 0, 0, \&playlistJump ]
    );

    $previousButton = Slim::Control::Request::addDispatch(
        [ 'button', '_buttoncode', '_time', '_orFunction' ],
        [ 1, 0, 0, \&buttonCommand ]
    );

    Slim::Control::Request::addDispatch(
        [ 'yandextitle', 'metadata', '_artist', '_title', '_cover' ],
        [ 1, 0, 0, \&metadataCommand ]
    );

    Slim::Control::Request::addDispatch(
        [ 'yandextitle', 'source', '_name' ],
        [ 1, 0, 0, \&sourceCommand ]
    );

    Slim::Control::Request::addDispatch(
        [ 'yandextitle', 'webhook', '_url' ],
        [ 0, 0, 0, \&webhookCommand ]
    );

    Slim::Formats::RemoteMetadata->registerProvider(
        match => qr{/api/yandex_station/},
        func  => \&metadataProvider,
    );

    Slim::Control::Request::subscribe(
        \&newMetadataSeen,
        [['newmetadata']]
    );

    $log->warn('YandexTitle 0.3.13: persistent Favorite labels across metadata refreshes, UTF-8 Station/Playlist labels and Alice transport bridge installed');
}

sub shutdownPlugin {
    Slim::Control::Request::unsubscribe(\&newMetadataSeen);

    if ($previousPlaylistPlay) {
        Slim::Control::Request::addDispatch(
            [ 'playlist', 'play', '_item', '_title', '_fadein' ],
            [ 1, 0, 0, $previousPlaylistPlay ]
        );
    }

    if ($previousPlaylistIndex) {
        Slim::Control::Request::addDispatch(
            [ 'playlist', 'index', '_index', '_fadein', '_noplay', '_seekdata' ],
            [ 1, 0, 0, $previousPlaylistIndex ]
        );
    }

    if ($previousPlaylistJump) {
        Slim::Control::Request::addDispatch(
            [ 'playlist', 'jump', '_index', '_fadein', '_noplay', '_seekdata' ],
            [ 1, 0, 0, $previousPlaylistJump ]
        );
    }

    if ($previousButton) {
        Slim::Control::Request::addDispatch(
            [ 'button', '_buttoncode', '_time', '_orFunction' ],
            [ 1, 0, 0, $previousButton ]
        );
    }
}

sub cleanText {
    my ($value, $max) = @_;

    return '' if !defined $value;

    $value =~ s/[\r\n\t]+/ /g;
    $value =~ s/\x00//g;
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/\s{2,}/ /g;

    if ($max && length($value) > $max) {
        $value = substr($value, 0, $max);
    }

    return $value;
}

sub displayUnicode {
    my ($value) = @_;

    return '' if !defined $value;

    return utf8::is_utf8($value)
        ? $value
        : decode_utf8($value);
}

sub displayTitle {
    return 'Алиса';
}

sub cleanupMetadata {
    my $now = time();

    for my $url (keys %META_BY_URL) {
        delete $META_BY_URL{$url}
            if !$META_BY_URL{$url}->{ts}
            || ($now - $META_BY_URL{$url}->{ts}) > 3600;
    }

    for my $player (keys %PENDING_BY_PLAYER) {
        delete $PENDING_BY_PLAYER{$player}
            if !$PENDING_BY_PLAYER{$player}->{ts}
            || ($now - $PENDING_BY_PLAYER{$player}->{ts}) > 30;
    }

    for my $player (keys %PENDING_SOURCE_BY_PLAYER) {
        delete $PENDING_SOURCE_BY_PLAYER{$player}
            if !$PENDING_SOURCE_BY_PLAYER{$player}->{ts}
            || ($now - $PENDING_SOURCE_BY_PLAYER{$player}->{ts}) > 30;
    }
}

sub webhookCommand {
    my $request = shift;

    my $url = cleanText($request->getParam('_url'), 512);

    if (
        $url !~ m{^https?://[^/]+/api/webhook/[A-Za-z0-9_-]+$}
    ) {
        $request->setStatusBadParams();
        return;
    }

    $prefs->set('ha_webhook_url', $url);

    $log->warn('YandexTitle: Home Assistant webhook configured');
    $request->setStatusDone();
}

sub sendTransportWebhook {
    my ($player_id, $command) = @_;

    my $url = $prefs->get('ha_webhook_url') || '';
    return 0 if $url eq '';

    my $zone = $ZONE_BY_PLAYER{$player_id} || '';

    my $payload =
        '{"player_id":"' . $player_id .
        '","zone":"' . $zone .
        '","command":"' . $command . '"}';

    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $response = shift;
            my $code = $response->code || 0;

            if ($code < 200 || $code >= 300) {
                $log->warn(
                    "YandexTitle: HA webhook returned HTTP $code"
                );
            }
        },
        sub {
            my ($response, $error) = @_;
            $log->warn(
                'YandexTitle: HA webhook failed: ' .
                ($error || 'unknown error')
            );
        },
        {
            timeout => 3,
            cache   => 0,
        }
    );

    $http->post(
        $url,
        'Content-Type' => 'application/json',
        $payload
    );

    return 1;
}

sub buttonCommand {
    my $request = shift;

    my $client = $request->client();
    my $code   = $request->getParam('_buttoncode');

    if (
        $client
        && defined $code
        && !ref $code
        && ($code eq 'fwd' || $code eq 'rew')
    ) {
        my $player_id = lc($client->id || '');
        my $url = Slim::Player::Playlist::url($client);

        if (
            $ZONE_BY_PLAYER{$player_id}
            && defined $url
            && !ref $url
            && $url =~ m{/api/yandex_station/}
        ) {
            my $command = $code eq 'fwd' ? 'next' : 'previous';

            if (sendTransportWebhook($player_id, $command)) {
                $log->info(
                    "YandexTitle: intercepted button $code " .
                    "for $player_id -> Alice $command"
                );

                $request->setStatusDone();
                return;
            }

            $log->warn(
                'YandexTitle: Alice button command not intercepted ' .
                'because HA webhook is not configured'
            );
        }
    }

    if ($previousButton) {
        return $previousButton->($request);
    }

    $request->setStatusBadDispatch();
}

sub handlePlaylistTransport {
    my ($request, $previous_handler, $transport_name) = @_;

    my $client = $request->client();
    my $index  = $request->getParam('_index');

    if (
        $client
        && defined $index
        && !ref $index
        && ($index eq '+1' || $index eq '-1')
    ) {
        my $player_id = lc($client->id || '');
        my $url = Slim::Player::Playlist::url($client);

        if (
            $ZONE_BY_PLAYER{$player_id}
            && defined $url
            && !ref $url
            && $url =~ m{/api/yandex_station/}
        ) {
            my $command = $index eq '+1' ? 'next' : 'previous';

            if (sendTransportWebhook($player_id, $command)) {
                $log->info(
                    "YandexTitle: intercepted playlist $transport_name $index " .
                    "for $player_id -> Alice $command"
                );

                $request->setStatusDone();
                return;
            }

            $log->warn(
                'YandexTitle: Alice transport command not intercepted ' .
                'because HA webhook is not configured'
            );
        }
    }

    if ($previous_handler) {
        return $previous_handler->($request);
    }

    $request->setStatusBadDispatch();
}

sub playlistIndex {
    my $request = shift;
    return handlePlaylistTransport(
        $request,
        $previousPlaylistIndex,
        'index'
    );
}

sub playlistJump {
    my $request = shift;
    return handlePlaylistTransport(
        $request,
        $previousPlaylistJump,
        'jump'
    );
}

sub sourceCommand {
    my $request = shift;
    my $client  = $request->client();

    if (!$client) {
        $request->setStatusBadParams();
        return;
    }

    cleanupMetadata();

    my $player_id = lc($client->id || '');

    if (!$ZONE_BY_PLAYER{$player_id}) {
        $request->setStatusBadParams();
        return;
    }

    my $name = cleanText(
        $request->getParam('_name'),
        140
    );

    if ($name eq '') {
        $request->setStatusBadParams();
        return;
    }

    my $display = $name =~ /^LMS\s*-\s*/i
        ? displayUnicode($name)
        : displayUnicode('LMS - ' . $name);

    $PENDING_SOURCE_BY_PLAYER{$player_id} = {
        name => $display,
        ts   => time(),
    };

    $ACTIVE_SOURCE_BY_PLAYER{$player_id} = {
        name => $display,
        ts   => time(),
    };

    $log->info(
        "YandexTitle: queued LMS source fallback for $player_id -> $display"
    );

    $request->setStatusDone();
}

sub applyPendingSource {
    my ($client, $player_id, $attempt) = @_;

    return if !$client;

    my $source = $PENDING_SOURCE_BY_PLAYER{$player_id};
    return if !$source;

    if (
        !$source->{ts}
        || (time() - $source->{ts}) > 30
    ) {
        delete $PENDING_SOURCE_BY_PLAYER{$player_id};
        return;
    }

    my $url = Slim::Player::Playlist::url($client);

    if (
        defined $url
        && !ref $url
        && $url ne ''
        && $url !~ m{/api/yandex_station/}
    ) {
        my $display = cleanText(
            $source->{name},
            180
        );

        Slim::Music::Info::setCurrentTitle(
            $url,
            $display,
            $client
        );

        $ACTIVE_SOURCE_BY_PLAYER{$player_id} = {
            name => $display,
            ts   => time(),
        };

        $IGNORE_NEXT_NEWMETADATA{$player_id} = time() + 1;

        Slim::Control::Request::notifyFromArray(
            $client,
            [ 'newmetadata' ]
        );

        delete $PENDING_SOURCE_BY_PLAYER{$player_id};

        $log->info(
            "YandexTitle: applied delayed LMS source for $player_id -> $display"
        );

        return;
    }

    $attempt ||= 0;

    if ($attempt < 8) {
        Slim::Utils::Timers::setTimer(
            $client,
            time() + 0.5,
            \&applyPendingSource,
            $player_id,
            $attempt + 1
        );
    }
    else {
        $log->warn(
            "YandexTitle: could not apply LMS source for $player_id because the new non-Alice URL did not become available"
        );
    }
}

sub metadataCommand {
    my $request = shift;
    my $client  = $request->client();

    if (!$client) {
        $request->setStatusBadParams();
        return;
    }

    cleanupMetadata();

    my $player_id = lc($client->id || '');

    delete $ACTIVE_SOURCE_BY_PLAYER{$player_id};
    delete $PENDING_SOURCE_BY_PLAYER{$player_id};

    if (!$ZONE_BY_PLAYER{$player_id}) {
        $request->setStatusBadParams();
        return;
    }

    my $meta = {
        artist => cleanText($request->getParam('_artist'), 100),
        title  => cleanText($request->getParam('_title'), 140),
        cover  => cleanText($request->getParam('_cover'), 1024),
        ts     => time(),
    };

    $PENDING_BY_PLAYER{$player_id} = $meta;

    my $url = Slim::Player::Playlist::url($client);

    if (
        defined $url
        && !ref $url
        && $url =~ m{/api/yandex_station/}
    ) {
        $META_BY_URL{$url} = { %{$meta} };

        my $display = displayTitle(
            $meta,
            $ZONE_BY_PLAYER{$player_id}
        );

        Slim::Music::Info::setCurrentTitle(
            $url,
            $display,
            $client
        );

        Slim::Control::Request::notifyFromArray(
            $client,
            [ 'newmetadata' ]
        );
    }

    $request->setStatusDone();
}

sub playlistPlay {
    my $request = shift;

    cleanupMetadata();

    my $client = $request->client();
    my $item   = $request->getParam('_item');
    my $title  = $request->getParam('_title');

    if (
        $client
        && defined $item
        && !ref $item
        && (!defined $title || $title eq '')
    ) {
        my $player_id = lc($client->id || '');

        if (
            $item =~ m{/api/yandex_station/}
            && (my $zone = $ZONE_BY_PLAYER{$player_id})
        ) {
            delete $ACTIVE_SOURCE_BY_PLAYER{$player_id};
            delete $PENDING_SOURCE_BY_PLAYER{$player_id};

            my $meta = $PENDING_BY_PLAYER{$player_id};

            if (
                $meta
                && $meta->{ts}
                && (time() - $meta->{ts}) <= 5
            ) {
                $META_BY_URL{$item} = { %{$meta} };

                my $display = displayTitle($meta, $zone);
                $request->addParam('_title', $display);

                delete $PENDING_BY_PLAYER{$player_id};
            }
            else {
                $request->addParam('_title', 'Алиса');
            }
        }
        else {
            my $favorite_display = '';
            my $matched_favorite = 0;

            my $favorites = Slim::Plugin::Favorites::OpmlFavorites->new($client);
            my $all_favorites = $favorites->all();

            for my $favorite (@{$all_favorites || []}) {
                next if !$favorite || ref($favorite) ne 'HASH';

                my $favorite_url = $favorite->{'url'};
                next if !defined $favorite_url || ref($favorite_url);
                next if $favorite_url ne $item;

                my $favorite_title = cleanText($favorite->{'title'}, 140);
                next if $favorite_title eq '';

                $favorite_display = displayUnicode(
                    'LMS - ' . $favorite_title
                );

                $PENDING_SOURCE_BY_PLAYER{$player_id} = {
                    name => $favorite_display,
                    ts   => time(),
                };

                $ACTIVE_SOURCE_BY_PLAYER{$player_id} = {
                    name => $favorite_display,
                    ts   => time(),
                };

                $matched_favorite = 1;

                $log->warn(
                    "YandexTitle: matched playlist play URL to Favorite " .
                    "for $player_id -> $favorite_display"
                );

                last;
            }

            if (
                !$matched_favorite
                && !$PENDING_SOURCE_BY_PLAYER{$player_id}
            ) {
                delete $ACTIVE_SOURCE_BY_PLAYER{$player_id};
            }

            if (my $source = $PENDING_SOURCE_BY_PLAYER{$player_id}) {
                if (
                    $source->{name}
                    && $source->{ts}
                    && (time() - $source->{ts}) <= 30
                ) {
                    Slim::Utils::Timers::killTimers(
                        $client,
                        \&applyPendingSource
                    );

                    Slim::Utils::Timers::setTimer(
                        $client,
                        time() + 0.75,
                        \&applyPendingSource,
                        $player_id,
                        0
                    );

                    $log->info(
                        "YandexTitle: scheduled LMS source for $player_id -> $source->{name}"
                    );
                }
            }
        }
    }

    if ($previousPlaylistPlay) {
        return $previousPlaylistPlay->($request);
    }

    $request->setStatusBadDispatch();
}

sub newMetadataSeen {
    my $request = shift;
    my $client  = $request->client();

    return if !$client;

    my $player_id = lc($client->id || '');
    return if !$ACTIVE_SOURCE_BY_PLAYER{$player_id};

    if (
        $IGNORE_NEXT_NEWMETADATA{$player_id}
        && $IGNORE_NEXT_NEWMETADATA{$player_id} >= time()
    ) {
        delete $IGNORE_NEXT_NEWMETADATA{$player_id};
        return;
    }

    delete $IGNORE_NEXT_NEWMETADATA{$player_id};

    my $url = Slim::Player::Playlist::url($client);

    return if !defined $url || ref $url || $url eq '';
    return if $url =~ m{/api/yandex_station/};

    Slim::Utils::Timers::killTimers(
        $client,
        \&applyActiveSource
    );

    Slim::Utils::Timers::setTimer(
        $client,
        time() + 0.10,
        \&applyActiveSource,
        $player_id
    );
}

sub applyActiveSource {
    my ($client, $player_id) = @_;

    return if !$client;

    my $source = $ACTIVE_SOURCE_BY_PLAYER{$player_id};
    return if !$source || !$source->{name};

    my $url = Slim::Player::Playlist::url($client);

    return if !defined $url || ref $url || $url eq '';
    return if $url =~ m{/api/yandex_station/};

    my $display = cleanText(
        $source->{name},
        180
    );

    Slim::Music::Info::setCurrentTitle(
        $url,
        $display,
        $client
    );

    $IGNORE_NEXT_NEWMETADATA{$player_id} = time() + 1;

    Slim::Control::Request::notifyFromArray(
        $client,
        [ 'newmetadata' ]
    );

    $log->info(
        "YandexTitle: refreshed active LMS source for $player_id -> $display"
    );
}

sub metadataProvider {
    my ($client, $url) = @_;

    cleanupMetadata();

    if (my $meta = $META_BY_URL{$url}) {
        my %result;

        $result{artist} = $meta->{artist}
            if $meta->{artist} ne '';

        $result{title} = $meta->{title}
            if $meta->{title} ne '';

        $result{cover} = $meta->{cover}
            if $meta->{cover} ne '';

        return \%result if %result;
    }

    if ($client) {
        my $player_id = lc($client->id || '');

        if (my $zone = $ZONE_BY_PLAYER{$player_id}) {
            return {
                title => $zone,
            };
        }
    }

    return {};
}

1;

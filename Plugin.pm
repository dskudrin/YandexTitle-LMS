package Plugins::YandexTitle::Plugin;

use strict;
use warnings;

use Slim::Control::Request;
use Slim::Formats::RemoteMetadata;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Playlist;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Time::HiRes qw(time);

my $log = logger('server.plugins');
my $prefs = preferences('plugin.yandextitle');

my $previousPlaylistPlay;
my $previousPlaylistIndex;

my %ZONE_BY_PLAYER = (
    'b8:27:eb:6d:75:2c' => 'Z1',
    'b8:27:eb:fa:8f:84' => 'Z2',
    'b8:27:eb:51:c7:73' => 'Z3',
    'b8:27:eb:fb:09:ef' => 'Z4',
    'bb:bb:b0:49:f0:4b' => 'DHC',
);

my %PENDING_BY_PLAYER;
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

    Slim::Control::Request::addDispatch(
        [ 'yandextitle', 'metadata', '_artist', '_title', '_cover' ],
        [ 1, 0, 0, \&metadataCommand ]
    );

    Slim::Control::Request::addDispatch(
        [ 'yandextitle', 'webhook', '_url' ],
        [ 0, 0, 0, \&webhookCommand ]
    );

    Slim::Formats::RemoteMetadata->registerProvider(
        match => qr{/api/yandex_station/},
        func  => \&metadataProvider,
    );

    $log->warn('YandexTitle 0.3.0-dev: metadata filter and Alice transport bridge installed');
}

sub shutdownPlugin {
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

sub displayTitle {
    my ($meta, $fallback) = @_;

    my $artist = $meta->{artist} || '';
    my $title  = $meta->{title}  || '';

    my $display;

    if ($artist ne '' && $title ne '') {
        $display = "Alice - $artist - $title";
    }
    elsif ($title ne '') {
        $display = "Alice - $title";
    }
    elsif ($artist ne '') {
        $display = "Alice - $artist";
    }
    else {
        $display = $fallback || 'Alice';
    }

    return cleanText($display, 180);
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

sub playlistIndex {
    my $request = shift;

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
                    "YandexTitle: intercepted playlist index $index " .
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

    if ($previousPlaylistIndex) {
        return $previousPlaylistIndex->($request);
    }

    $request->setStatusBadDispatch();
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
        && $item =~ m{/api/yandex_station/}
        && (!defined $title || $title eq '')
    ) {
        my $player_id = lc($client->id || '');

        if (my $zone = $ZONE_BY_PLAYER{$player_id}) {
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
                $request->addParam('_title', $zone);
            }
        }
    }

    if ($previousPlaylistPlay) {
        return $previousPlaylistPlay->($request);
    }

    $request->setStatusBadDispatch();
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

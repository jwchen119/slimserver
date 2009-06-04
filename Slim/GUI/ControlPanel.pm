package Slim::GUI::ControlPanel::MainFrame;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Frame';

use Slim::Utils::Light;
use File::Spec::Functions;

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_NOTEBOOK_PAGE_CHANGED);

use Slim::GUI::ControlPanel::InitialSettings;
use Slim::GUI::ControlPanel::Settings;
use Slim::GUI::ControlPanel::Music;
use Slim::GUI::ControlPanel::Advanced;
use Slim::GUI::ControlPanel::Status;
use Slim::GUI::ControlPanel::Diagnostics;
use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

use constant PAGE_STATUS => 3;
use constant PAGE_SCAN   => 1;

my $pollTimer;
my $btnOk;

my $svcMgr = Slim::Utils::ServiceManager->new();

sub new {
	my $ref = shift;
	my $args = shift;

	Slim::Utils::OSDetect::init();

	# if we're running for the first time, show the SN page
	my $initialSetup = $svcMgr->isRunning() && !Slim::GUI::ControlPanel->getPref('wizardDone');

	my $self = $ref->SUPER::new(
		undef,
		-1,
		$initialSetup ? string('WELCOME_TO_SQUEEZECENTER') : string('CONTROLPANEL_TITLE'),
		[-1, -1],
		Slim::Utils::OSDetect::isWindows() ? [550, 610] : [700, 700],
		wxMINIMIZE_BOX | wxMAXIMIZE_BOX | wxCAPTION | wxCLOSE_BOX | wxSYSTEM_MENU | wxRESIZE_BORDER,
		'WELCOME_TO_SQUEEZECENTER'
	);

	my $file = $self->_fixIcon('SqueezeCenter.ico');
	if ($file  && (my $icon = Wx::Icon->new($file, wxBITMAP_TYPE_ICO)) ) {
		$self->SetIcon($icon);
	}

	my $panel     = Wx::Panel->new($self);
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$pollTimer = Slim::GUI::ControlPanel::Timer->new();
	
	$btnOk = Slim::GUI::ControlPanel::OkButton->new( $panel, wxID_OK, string('OK') );
	EVT_BUTTON( $self, $btnOk, sub {
		$btnOk->do($svcMgr->checkServiceState());
		$_[0]->Destroy;
	} );

	if ($initialSetup) {
		
		$mainSizer->Add(Slim::GUI::ControlPanel::InitialSettings->new($panel, $self), 1, wxALL | wxGROW, 10);
		
		Slim::GUI::ControlPanel->setPref('wizardDone', 1);
	}
	
	else {

		my $notebook = Wx::Notebook->new($panel);
	
		EVT_NOTEBOOK_PAGE_CHANGED($self, $notebook, sub {
			my ($self, $event) = @_;
	
			eval {
				my $child = $notebook->GetPage($notebook->GetSelection());
				if ($child && $child->can('_update')) {
					$child->_update($event);
				};
			}
		});
	
		$notebook->AddPage(Slim::GUI::ControlPanel::Settings->new($notebook, $self), string('BASIC_SERVER_SETTINGS'), 1);
		$notebook->AddPage(Slim::GUI::ControlPanel::Music->new($notebook, $self), string('CONTROLPANEL_MUSIC_LIBRARY'));
		$notebook->AddPage(Slim::GUI::ControlPanel::Advanced->new($notebook, $self, $args), string('ADVANCED_SETTINGS'));
		$notebook->AddPage(Slim::GUI::ControlPanel::Status->new($notebook), string('INFORMATION'));
		$notebook->AddPage(Slim::GUI::ControlPanel::Diagnostics->new($notebook, $self, $args), string('CONTROLPANEL_DIAGNOSTICS'));
	
		$mainSizer->Add($notebook, 1, wxALL | wxGROW, 10);
	}
	
	my $footerSizer = Wx::BoxSizer->new(wxHORIZONTAL);
	
	if ($file = $self->_fixIcon('logitech-logo.png')) {
		Wx::Image::AddHandler(Wx::PNGHandler->new());
		my $icon = Wx::StaticBitmap->new( $panel, -1, Wx::Bitmap->new($file, wxBITMAP_TYPE_PNG) );
		$footerSizer->Add($icon, 0, wxLEFT | wxBOTTOM, 5);
	}
	
	my $btnsizer = Wx::StdDialogButtonSizer->new();
	$btnsizer->AddButton($btnOk);

	my $btnApply = Wx::Button->new( $panel, wxID_APPLY, string('APPLY') );
	EVT_BUTTON( $self, $btnApply, sub {
		$btnOk->do($svcMgr->checkServiceState());
	} );

	$btnsizer->AddButton($btnApply);
	
	my $btnCancel = Wx::Button->new( $panel, wxID_CANCEL, string('CANCEL') );

	EVT_BUTTON( $self, $btnCancel, sub {
		$_[0]->Destroy;
	} );

	$btnsizer->AddButton($btnCancel);

	$btnsizer->Realize();

	my $footerSizer2 = Wx::BoxSizer->new(wxVERTICAL); 
	$footerSizer2->Add($btnsizer, 0, wxEXPAND);
	$footerSizer2->AddSpacer(20);
	$footerSizer2->Add(Wx::StaticText->new($panel, -1, string('COPYRIGHT')), 0, wxALIGN_RIGHT | wxRIGHT, 3);

	$footerSizer->Add($footerSizer2, wxEXPAND);
	$mainSizer->Add($footerSizer, 0, wxLEFT | wxRIGHT | wxGROW, 8);

	$panel->SetSizer($mainSizer);	
	
	$pollTimer->Start(5000, wxTIMER_CONTINUOUS);
	$pollTimer->Notify();

	return $self;
}

sub addApplyHandler {
	my $self = shift;
	$btnOk->addActionHandler(@_);
}

sub addStatusListener {
	my $self = shift;
	$pollTimer->addListener(@_);
}

sub checkServiceStatus {
	$pollTimer->Notify();
}

sub _fixIcon {
	my $self = shift;
	my $iconFile = shift;

	return unless Slim::Utils::OSDetect::isWindows();

	# set the application icon
	my $file = "../platforms/win32/res/$iconFile";

	if (!-f $file && defined $PerlApp::VERSION) {
		$file = PerlApp::extract_bound_file($iconFile);
	}

	return $file if -f $file;
}

1;


# Our own timer object, checking for SC availability
package Slim::GUI::ControlPanel::Timer;

use base 'Wx::Timer';
use Slim::Utils::ServiceManager;

my %listeners;

sub addListener {
	my ($self, $item, $callback) = @_;

	# if no callback is given, then enable the element if SC is running, or disable otherwise
	$listeners{$item} = $callback || sub { $item->Enable($_[0] == SC_STATE_RUNNING) };
}

sub Notify {
	my $status = $svcMgr->checkServiceState();

	foreach my $listener (keys %listeners) {

		if (my $callback = $listeners{$listener}) {
			&$callback($status);
		}
	}
}

1;


# Ok button will apply our changes
package Slim::GUI::ControlPanel::OkButton;

use base 'Wx::Button';

sub new {
	my $self = shift;
		
	$self = $self->SUPER::new(@_);
	$self->{actionHandlers} = {};
	$self->SetDefault();
	
	return $self;
}

sub addActionHandler {
	my ($self, $item, $callback) = @_;
	$self->{actionHandlers}->{$item} = $callback;
}

sub do {
	my ($self, $status) = @_;
	
	foreach my $actionHandler (keys %{ $self->{actionHandlers} }) {
		
		if (my $action = $self->{actionHandlers}->{$actionHandler}) {
			&$action($status);
		}
	}
}

1;


# The CleanupGUI main class
package Slim::GUI::ControlPanel;

use base 'Wx::App';
use Wx qw(:everything);
use LWP::UserAgent;
use JSON::XS qw(to_json from_json);

use Slim::Utils::ServiceManager;

my $args;

my $credentials = {};

sub new {
	my $self = shift;
	$args    = shift;

	$self = $self->SUPER::new();

	return $self;
}

sub OnInit {
	my $self = shift;
	my $frame;
	
	$frame = Slim::GUI::ControlPanel::MainFrame->new($args); 
	
	$frame->Show( 1 );
}

# the following subs are static methods to deliver some commonly used services
sub getBaseUrl {
	my $self = shift;
	return 'http://127.0.0.1:' . $self->getPref('httpport');
}

sub setPref {
	my ($self, $pref, $value) = @_;
	
	$self->serverRequest('pref', $pref, $value);
}

sub getPref {
	my ($self, $pref, $file) = @_;
	$file ||= '';

	my $value;
	
	# if SC is running, use the CLI, otherwise read the prefs file from disk
	if ($svcMgr->isRunning()) {

		if ($file) {
			$file =~ s/\.prefs$//; 
			$file = "plugin.$file:";
		}
	
		$value = $self->serverRequest('pref', $file . $pref, '?');

		if (ref $value) {
			$value = $value->{'_p2'};
		}
	}
	
	else {
		$value = Slim::Utils::Light::getPref($pref, $file);
	}
	
	return $value;
}


sub serverRequest {
	my $self = shift;
	my $postdata;
	
	return unless $svcMgr->isRunning();

	eval { $postdata = '{"id":1,"method":"slim.request","params":["",' . to_json(\@_) . ']}' };

	return if $@ || !$postdata;

	my $httpPort = Slim::Utils::Light::getPref('httpport') || 9000;
	my $baseUrl  = "127.0.0.1:$httpPort";

	my $req = HTTP::Request->new( 
		'POST',
		"http://$baseUrl/jsonrpc.js",
	);
	$req->header('Content-Type' => 'text/plain');

	$req->content($postdata);
	
	my $ua = LWP::UserAgent->new();
	$ua->timeout(5);
	
	if ($credentials && $credentials->{username} && $credentials->{password}) {
		$ua->credentials($baseUrl, "SqueezeCenter", $credentials->{username}, $credentials->{password});
	}

	my $response = $ua->request($req);

	# check whether authentication is needed
	while ($response->code == 401) {
		my $loginDialog = Slim::GUI::ControlPanel::LoginDialog->new();
		
		if ($loginDialog->ShowModal() == wxID_OK) {
		
			$credentials = {
				username => $loginDialog->username,
				password => $loginDialog->password,
			};
		
			$ua->credentials($baseUrl, "SqueezeCenter", $credentials->{username}, $credentials->{password});
		
			$response = $ua->request($req);
		}
		
		else {
			exit;
		}
		
		$loginDialog->Destroy();
	}
	
	my $content;
	$content = $response->decoded_content if ($response);

	if ($content) {
		eval {
			$content = from_json($content);
			$content = $content->{result};
		}
	}

	return ref $content ? $content : { msg => $content };
}

1;


# Ok button will apply our changes
package Slim::GUI::ControlPanel::LoginDialog;

use base 'Wx::Dialog';
use Wx qw(:everything);
use Slim::Utils::Light;

my ($username, $password);

sub new {
	my $self = shift;
		
	$self = $self->SUPER::new(undef, -1, string('LOGIN'), [-1, -1], [350, 220], wxDEFAULT_DIALOG_STYLE);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$mainSizer->Add(Wx::StaticText->new($self, -1, string('CONTROLPANEL_AUTHENTICATION_REQUIRED')), 0, wxALL, 10);

	$mainSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_USERNAME') . string('COLON')), 0, wxLEFT | wxRIGHT, 10);
	$username = Wx::TextCtrl->new($self, -1, '', [-1, -1], [330, -1]);
	$mainSizer->Add($username, 0, wxALL, 10);
	
	$mainSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_PASSWORD') . string('COLON')), 0, wxLEFT | wxRIGHT, 10);
	$password = Wx::TextCtrl->new($self, -1, '', [-1, -1], [330, -1], wxTE_PASSWORD);
	$mainSizer->Add($password, 0, wxALL, 10);
	
	$mainSizer->AddStretchSpacer();

	my $btnsizer = Wx::StdDialogButtonSizer->new();
	$btnsizer->AddButton(Wx::Button->new($self, wxID_OK, string('OK')));
	$btnsizer->AddButton(Wx::Button->new($self, wxID_CANCEL, string('CANCEL')));
	$btnsizer->Realize();
	$mainSizer->Add($btnsizer, 0, wxALL | wxGROW, 10);

	$self->SetSizer($mainSizer);

	$self->Centre();
		
	return $self;
}

sub username {
	return $username->GetValue();
}


sub password {
	return $password->GetValue();
}

1;

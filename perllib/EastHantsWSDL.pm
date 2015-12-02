package EastHantsWSDL;

# -- generated by SOAP::Lite (v0.60) for Perl -- soaplite.com -- Copyright (C) 2000-2001 Paul Kulchenko --
# -- generated from http://www.easthants.gov.uk/forms.nsf/InputFeedback?WSDL [Thu Oct 16 12:31:57 2008]

my %methods = (
  INPUTFEEDBACK => {
    endpoint => 'http://91.224.27.33/forms.nsf/InputFeedback?OpenWebService',
    soapaction => 'INPUTFEEDBACK',
    uri => 'urn:DefaultNamespace',
    parameters => [
      SOAP::Data->new(name => 'STRSERVICENAME', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRREMOTECREATEDBY', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRSALUTATION', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRFIRSTNAME', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRNAME', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STREMAIL', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRTELEPHONE', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRHOUSENONAME', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRSTREET', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRTOWN', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRCOUNTY', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRCOUNTRY', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRPOSTCODE', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRCOMMENTS', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRFURTHERINFO', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'STRIMAGEURL', type => 'xsd:string', attr => {}),
    ],
  },
);

use SOAP::Lite; # +trace => [qw(debug)];
use Exporter;
use Carp ();

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

no strict 'refs';
for my $method (@EXPORT_OK) {
  my %method = %{$methods{$method}};
  *$method = sub {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__) 
      ? ref $_[0] ? shift # OBJECT
                  # CLASS, either get self or create new and assign to self
                  : (shift->self || __PACKAGE__->self(__PACKAGE__->new))
      # function call, either get self or create new and assign to self
      : (__PACKAGE__->self || __PACKAGE__->self(__PACKAGE__->new));
    $self->proxy($method{endpoint} || Carp::croak "No server address (proxy) specified") unless $self->proxy;
    my @templates = @{$method{parameters}};
    my $som = $self
      -> endpoint($method{endpoint})
      -> uri($method{uri})
      -> on_action(sub{qq!"$method{soapaction}"!})
      -> call($method => map {@templates ? shift(@templates)->value($_) : $_} @_); 
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result 
                                        : $som;
  }
}

sub AUTOLOAD {
  my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
  return if $method eq 'DESTROY';

  die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

1;
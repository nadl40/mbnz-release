#************************************************************************************#
#                                                                                    #
# a package to get elements from shadow root                                         #
# after https://stackoverflow.com/questions/73724414/selenium-perl-handle-shadow-dom #
# works only with css                                                                #
#                                                                                    #
#************************************************************************************#
package MyShadow {
   sub new {
      my ($class, %attrs) = @_;
      my $shadow_root = $attrs{driver}->execute_script('return arguments[0].shadowRoot', $attrs{shadow_host});
      return undef if ! $shadow_root;
      $attrs{shadow_root} = $shadow_root;
      bless \%attrs, $class;
   }
   sub find_element {
      my ($self, $target, $scheme) = @_;
      die "scheme=$scheme is not supported. Only css is supported" if $scheme ne 'css';
      return $self->{driver}->execute_script(
                 "return arguments[0].querySelector(arguments[1])",
                 $self->{shadow_root},
                 $target
             );
   }
   sub find_elements {
      my ($self, $target, $scheme) = @_;
      die "scheme=$scheme is not supported. Only css is supported" if $scheme ne 'css';
      return $self->{driver}->execute_script(
                "return arguments[0].querySelectorAll(arguments[1])",
                $self->{shadow_root},
                $target
      );
   }
}
1;

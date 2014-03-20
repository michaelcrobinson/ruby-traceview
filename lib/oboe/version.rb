# Copyright (c) 2013 AppNeta, Inc.
# All rights reserved.

module Oboe
  module Version
    MAJOR = 2
    MINOR = 6 
    PATCH = 2 
    BUILD = "dev3"

    STRING = [MAJOR, MINOR, PATCH, BUILD].compact.join('.')
  end
end

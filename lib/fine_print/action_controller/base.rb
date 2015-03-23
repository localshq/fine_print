module FinePrint
  module ActionController
    module Base

      def self.included(base)
        base.extend(ClassMethods)
      end

      # Accepts an array of contract names and an options hash
      # Checks if the current user has signed the given contracts
      # and calls fine_print_redirect if not
      # Options relevant to FinePrint are passed to fine_print_redirect
      def fine_print_require(*names)
        options = names.last.is_a?(Hash) ? names.pop : {}
        fp_opts = options.slice(*FinePrint::Configuration::CONTROLLER_OPTIONS)

        # Convert names to an array of Strings
        contract_names = names.flatten.collect{|c| c.to_s}

        # Return quietly if all contracts skipped
        return if contract_names.blank?

        user = instance_exec &FinePrint.config.current_user_proc

        can_sign = instance_exec(user, &FinePrint.config.authenticate_user_proc)

        return if !can_sign || performed?

        unsigned_contracts = FinePrint.get_unsigned_contracts(
          user, name: contract_names
        )

        # Return quietly if all contracts signed
        return if unsigned_contracts.blank?

        fine_print_redirect(user, unsigned_contracts, fp_opts)
      end

      # Accepts a user, an array of contract ids to be signed and an options hash
      # Calls the `redirect_to_contracts_proc` with the given parameters
      def fine_print_redirect(user, *contracts)
        options = contracts.last.is_a?(Hash) ? contracts.pop : {}
        contracts = contracts.flatten

        blk = options[:redirect_to_contracts_proc] || \
              FinePrint.config.redirect_to_contracts_proc

        # Use action_interceptor to save the current url
        store_url key: :fine_print_return_to

        instance_exec user, contracts, &blk
      end

      # Accepts no arguments
      # Redirects the user back to the url they were at before
      # `fine_print_redirect` redirected them
      def fine_print_return
        redirect_back key: :fine_print_return_to
      end

      protected

      def fine_print_skipped_contract_names
        @fine_print_skipped_contract_names ||= []
      end

      module ClassMethods
        # Accepts an array of contract names and an options hash
        # Adds a before_filter to the current controller that will check if the
        # current user has signed the given contracts and call the sign_proc if appropriate
        # Options relevant to FinePrint are passed to fine_print_sign, while
        # other options are passed to the before_filter
        def fine_print_require(*names)
          options = names.last.is_a?(Hash) ? names.pop : {}
          f_opts = options.except(*FinePrint::Configuration::CONTROLLER_OPTIONS)

          # Convert names to an array of Strings
          contract_names = names.flatten.collect{|c| c.to_s}

          class_exec do
            before_filter(f_opts) do |controller|
              skipped_contract_names = fine_print_skipped_contract_names
              unskipped_contract_names = contract_names - skipped_contract_names
              controller.fine_print_require(unskipped_contract_names, options)
            end
          end
        end

        # Accepts an array of contract names and an options hash
        # Excludes the given contracts from the `fine_print_require`
        # check for this controller and subclasses
        # Options are passed to prepend_before_filter
        def fine_print_skip(*names)
          options = names.last.is_a?(Hash) ? names.pop : {}

          # Convert names to an array of Strings
          contract_names = names.flatten.collect{|c| c.to_s}

          class_exec do
            prepend_before_filter(options) do |controller|
              controller.fine_print_skipped_contract_names.push(*contract_names)
            end
          end
        end
      end

    end
  end
end

::ActionController::Base.send :include, FinePrint::ActionController::Base

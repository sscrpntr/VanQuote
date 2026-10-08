class ProfilesController < ApplicationController
  def show
  end

  def update
    if Current.user.update(profile_params)
      redirect_to profile_path, notice: "Perfil actualizado correctamente."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :email_address,
      :phone
    )
  end
end
